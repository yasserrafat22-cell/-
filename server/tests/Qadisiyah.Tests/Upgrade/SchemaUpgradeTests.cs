using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Qadisiyah.Application;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Security;

namespace Qadisiyah.Tests.Upgrade;

/// <summary>
/// سيناريو تحديث حقيقي على مستوى قاعدة البيانات: قاعدة بمخطط الإصدار السابق
/// (InitialIdentity، وهو المثبت على سيرفر التجربة) فيها مدير غيّر كلمة مروره،
/// ثم يعمل الإصدار الجديد عليها كما يحدث عند التحديث.
/// </summary>
public sealed class SchemaUpgradeTests : IAsyncLifetime
{
    private const string PreviousVersionMigration = "20261027181853_InitialIdentity";

    private static readonly string ConnectionString =
        Infrastructure.ApiFactory.ConnectionString.Replace("qadisiyah_test", "qadisiyah_upgrade_test", StringComparison.Ordinal);

    private static AppDbContext NewContext() => new(new DbContextOptionsBuilder<AppDbContext>()
        .UseNpgsql(ConnectionString).UseSnakeCaseNamingConvention().Options);

    public async Task InitializeAsync()
    {
        await using var db = NewContext();
        await db.Database.EnsureDeletedAsync();
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private static DbInitializer Initializer(AppDbContext db, string? bootstrapPassword) => new(
        db, new PasswordHasher(),
        new BootstrapOptions { AdminPassword = bootstrapPassword },
        TimeProvider.System, NullLogger<DbInitializer>.Instance);

    [Fact]
    public async Task Upgrading_from_the_previous_version_keeps_users_passwords_and_sessions()
    {
        var hasher = new PasswordHasher();
        Guid adminId;
        string passwordHash;
        Guid stamp;

        // 1) الإصدار السابق: مخطط InitialIdentity فقط، والمدير غيّر كلمة المرور المؤقتة.
        await using (var db = NewContext())
        {
            await db.GetService<IMigrator>().MigrateAsync(PreviousVersionMigration);
            var applied = await db.Database.GetAppliedMigrationsAsync();
            Assert.Equal([PreviousVersionMigration], applied);

            await db.Database.ExecuteSqlRawAsync("""
                INSERT INTO roles (id, code, name_ar, is_system) VALUES
                  ('01a17e97-0000-7000-8000-000000000001', 'system_admin', 'مدير النظام', true);
                INSERT INTO role_permissions (role_id, permission) VALUES
                  ('01a17e97-0000-7000-8000-000000000001', 'users.manage');
                """);
            adminId = Guid.CreateVersion7();
            passwordHash = hasher.Hash("ChangedByAdmin2026");
            stamp = Guid.NewGuid();
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO users (id, username, display_name, password_hash, is_active, must_change_password,
                                   security_stamp, failed_login_count, created_at, updated_at)
                VALUES ({adminId}, 'admin', 'مدير النظام', {passwordHash}, true, false, {stamp}, 0, now(), now());
                INSERT INTO user_roles (user_id, role_id) VALUES ({adminId}, '01a17e97-0000-7000-8000-000000000001');
                INSERT INTO devices (id, name, last_user_id, first_seen_at, last_seen_at)
                VALUES ('0192f0c0-aaaa-7000-8000-000000000001', 'android', {adminId}, now(), now());
                """);
        }

        // 2) الإصدار الجديد يبدأ على نفس القاعدة، مع كلمة مرور bootstrap مختلفة في .env.
        await using (var db = NewContext())
        {
            await Initializer(db, bootstrapPassword: "SomeOtherBootstrap1").InitializeAsync();
            await Initializer(db, bootstrapPassword: "SomeOtherBootstrap1").InitializeAsync();
        }

        // 3) لا شيء من بيانات الإصدار السابق تغير، والجداول الجديدة موجودة ومهيأة.
        await using (var db = NewContext())
        {
            var applied = (await db.Database.GetAppliedMigrationsAsync()).ToList();
            Assert.Equal(PreviousVersionMigration, applied[0]);
            Assert.Empty(await db.Database.GetPendingMigrationsAsync());

            var admin = await db.Users.SingleAsync();
            Assert.Equal(adminId, admin.Id);
            Assert.Equal(passwordHash, admin.PasswordHash);
            Assert.True(hasher.Verify(admin.PasswordHash, "ChangedByAdmin2026"));
            Assert.False(hasher.Verify(admin.PasswordHash, "SomeOtherBootstrap1"));
            Assert.False(admin.MustChangePassword);
            Assert.Equal(stamp, admin.SecurityStamp);
            Assert.Equal(1, await db.Devices.CountAsync());

            // الدور الموجود لم تُغير صلاحياته؛ والأدوار الناقصة أُضيفت.
            Assert.Equal(["users.manage"], await db.RolePermissions
                .Where(rp => rp.RoleId == Guid.Parse("01a17e97-0000-7000-8000-000000000001"))
                .Select(rp => rp.Permission).ToListAsync());
            Assert.Equal(4, await db.Roles.CountAsync());

            Assert.True(await db.Materials.AnyAsync(m => m.Code == "PVC"));
            Assert.True(await db.Units.AnyAsync(u => u.Code == "ton" && u.FactorToKg == 1000));
            Assert.Equal(adminId, (await db.Representatives.SingleAsync()).UserId);
        }
    }

    [Fact]
    public async Task Reference_data_edited_by_the_admin_is_not_overwritten_on_update()
    {
        await using (var db = NewContext())
            await Initializer(db, "Bootstrap2026").InitializeAsync();

        await using (var db = NewContext())
        {
            var ton = await db.Units.SingleAsync(u => u.Code == "ton");
            ton.NameAr = "طن متري";
            var other = await db.LookupItems.SingleAsync(l => l.Category == "activity_type" && l.Code == "other");
            other.IsActive = false;
            await db.SaveChangesAsync();
        }

        await using (var db = NewContext())
            await Initializer(db, "Bootstrap2026").InitializeAsync();

        await using (var db = NewContext())
        {
            Assert.Equal("طن متري", (await db.Units.SingleAsync(u => u.Code == "ton")).NameAr);
            Assert.False((await db.LookupItems.SingleAsync(l => l.Category == "activity_type" && l.Code == "other")).IsActive);
            Assert.Equal(1, await db.Users.CountAsync());
            Assert.Equal(1, await db.Units.CountAsync(u => u.Code == "ton"));
        }
    }
}
