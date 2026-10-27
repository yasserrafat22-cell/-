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
        await db.Database.MigrateAsync(ct);
        await SeedRolesAsync(ct);
        await SeedAdminAsync(ct);
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
