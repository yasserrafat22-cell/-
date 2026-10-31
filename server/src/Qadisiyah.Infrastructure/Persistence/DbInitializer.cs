using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Qadisiyah.Application;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Infrastructure.Persistence;

public sealed class BootstrapOptions
{
    public const string Section = "Bootstrap";

    public string AdminUsername { get; set; } = "admin";
    public string AdminDisplayName { get; set; } = "مدير النظام";

    /// <summary>
    /// تُمرر عبر متغير البيئة <c>Bootstrap__AdminPassword</c> ولا تُكتب في الإعدادات.
    /// تُستخدم مرة واحدة فقط عند عدم وجود أي مستخدم، ويُجبر المدير على تغييرها.
    /// </summary>
    public string? AdminPassword { get; set; }
}

public sealed partial class DbInitializer(
    AppDbContext db,
    IPasswordHasher hasher,
    BootstrapOptions bootstrap,
    TimeProvider clock,
    ILogger<DbInitializer> logger)
{
    public async Task InitializeAsync(CancellationToken ct = default)
    {
        // ترحيلات تراكمية: تُطبق الناقصة فقط على قاعدة البيانات الحالية دون حذف بياناتها.
        await db.Database.MigrateAsync(ct);
        await SeedRolesAsync(ct);
        await SeedAdminAsync(ct);
        await ReferenceSeed.SeedAsync(db, ct);
        await ReferenceSeed.EnsureOwnerCatalogAsync(db, ct);
        await ReferenceSeed.EnsureRepresentativesAsync(db, ct);
        await VerifyPendingGradesAsync(ct);
    }

    private const string PendingGradesKey = "catalog.pending_verified_v1";

    /// <summary>
    /// مرة واحدة عند الترقية لـ 0.5: الـ Grades «بانتظار التحقق» التي لها شركة ولا يوجد
    /// غيرها بنفس الكود لنفس الخامة تُعتمد. المتعارضة أو بلا شركة تبقى للمدير يراجعها،
    /// وتاريخها وروابطها لا تتغير.
    /// </summary>
    private async Task VerifyPendingGradesAsync(CancellationToken ct)
    {
        if (await db.AppSettings.AnyAsync(s => s.Key == PendingGradesKey, ct))
            return;
        var pending = await db.Grades.Where(g => !g.IsVerified && g.ManufacturerId != null).ToListAsync(ct);
        foreach (var grade in pending)
        {
            var conflicting = await db.Grades.AnyAsync(g => g.Id != grade.Id && g.MaterialId == grade.MaterialId
                && g.NormalizedCode == grade.NormalizedCode, ct);
            if (!conflicting)
                grade.IsVerified = true;
        }
        db.AppSettings.Add(new Domain.Reference.AppSetting { Key = PendingGradesKey, Value = "done" });
        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// ينشئ الأدوار المبدئية الناقصة فقط؛ لا يغير صلاحيات دور موجود لأن
    /// المدير قد يكون عدّلها.
    /// </summary>
    private async Task SeedRolesAsync(CancellationToken ct)
    {
        var existing = await db.Roles.Select(r => r.Code).ToListAsync(ct);
        foreach (var definition in SystemRoles.Defaults.Where(d => !existing.Contains(d.Code)))
        {
            var role = new Role { Code = definition.Code, NameAr = definition.NameAr, IsSystem = true };
            role.Permissions.AddRange(definition.Permissions.Select(p => new RolePermission { Permission = p }));
            db.Roles.Add(role);
        }
        await db.SaveChangesAsync(ct);
        await ApplyUpgradeGrantsAsync(ct);
    }

    private const string GrantsVersionKey = "permissions.grants_version";

    /// <summary>
    /// يضيف الصلاحيات الجديدة لكل إصدار مرة واحدة للأدوار الموجودة (إضافة فقط).
    /// صلاحية أزالها المدير لاحقًا لا تُعاد في التحديثات التالية.
    /// </summary>
    private async Task ApplyUpgradeGrantsAsync(CancellationToken ct)
    {
        var setting = await db.AppSettings.FirstOrDefaultAsync(s => s.Key == GrantsVersionKey, ct);
        var applied = int.TryParse(setting?.Value, out var v) ? v : 1;
        var pending = SystemRoles.UpgradeGrants.Where(g => g.Version > applied).ToList();
        if (pending.Count == 0)
            return;

        var roles = await db.Roles.Include(r => r.Permissions).ToListAsync(ct);
        foreach (var (_, code, permissions) in pending)
        {
            var role = roles.FirstOrDefault(r => r.Code == code);
            if (role is null)
                continue;
            foreach (var permission in permissions.Where(p => role.Permissions.All(rp => rp.Permission != p)))
                role.Permissions.Add(new RolePermission { RoleId = role.Id, Permission = permission });
        }
        var latest = pending.Max(g => g.Version).ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (setting is null)
            db.AppSettings.Add(new Domain.Reference.AppSetting { Key = GrantsVersionKey, Value = latest });
        else
            setting.Value = latest;
        await db.SaveChangesAsync(ct);
    }

    private async Task SeedAdminAsync(CancellationToken ct)
    {
        if (await db.Users.AnyAsync(ct))
            return;

        if (string.IsNullOrWhiteSpace(bootstrap.AdminPassword))
        {
            LogNoBootstrapPassword(logger);
            return;
        }

        var now = clock.GetUtcNow();
        var admin = new User
        {
            Username = User.NormalizeUsername(bootstrap.AdminUsername),
            DisplayName = bootstrap.AdminDisplayName,
            PasswordHash = hasher.Hash(bootstrap.AdminPassword),
            MustChangePassword = true,
            CreatedAt = now,
            UpdatedAt = now,
        };
        var adminRole = await db.Roles.FirstAsync(r => r.Code == SystemRoles.SystemAdmin, ct);
        admin.Roles.Add(new UserRole { RoleId = adminRole.Id });
        db.Users.Add(admin);
        db.AuditEntries.Add(new AuditEntry
        {
            At = now,
            Action = "users.bootstrap_admin_created",
            EntityType = "user",
            EntityId = admin.Id,
        });
        await db.SaveChangesAsync(ct);
        LogAdminCreated(logger, admin.Username);
    }

    [LoggerMessage(Level = LogLevel.Warning,
        Message = "No users exist and Bootstrap:AdminPassword is not set; no administrator was created.")]
    private static partial void LogNoBootstrapPassword(ILogger logger);

    [LoggerMessage(Level = LogLevel.Information,
        Message = "Bootstrap administrator '{Username}' created; password change is required on first login.")]
    private static partial void LogAdminCreated(ILogger logger, string username);
}
