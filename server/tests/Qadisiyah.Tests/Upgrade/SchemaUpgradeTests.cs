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
    private const string Phase3Migration = "20261028005251_Phase3CoreData";

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

    [Fact]
    public async Task Upgrading_from_phase3_keeps_grades_and_their_links_without_guessing_a_manufacturer()
    {
        var material = Guid.CreateVersion7();
        var grade = Guid.CreateVersion7();
        var unit = Guid.CreateVersion7();
        var party = Guid.CreateVersion7();
        var interest = Guid.CreateVersion7();
        var order = Guid.CreateVersion7();
        var line = Guid.CreateVersion7();

        // 1) قاعدة بمخطط المرحلة 3 فيها Grade مستخدم في اهتمام عميل وبند طلب.
        await using (var db = NewContext())
        {
            await db.GetService<IMigrator>().MigrateAsync(Phase3Migration);
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO materials (id, code, name_ar, sort_order, is_active) VALUES ({material}, 'PVC', 'بي في سي', 0, true);
                INSERT INTO grades (id, material_id, code, normalized_code, is_active) VALUES ({grade}, {material}, 'SG-5', 'SG5', true);
                INSERT INTO units (id, code, name_ar, factor_to_kg, sort_order, is_active) VALUES ({unit}, 'ton', 'طن', 1000, 0, true);
                INSERT INTO parties (id, name, normalized_name, is_customer, is_supplier, country_code,
                                     created_at, created_by, updated_at, updated_by)
                VALUES ({party}, 'عميل تجريبي', 'عميل تجريبي', true, false, 'EG', now(), {party}, now(), {party});
                INSERT INTO customer_interests (id, party_id, material_id, grade_id) VALUES ({interest}, {party}, {material}, {grade});
                INSERT INTO orders (id, customer_id, order_date, stage, on_hold, created_at, created_by, updated_at, updated_by)
                VALUES ({order}, {party}, '2026-10-20', 'Confirmed', false, now(), {party}, now(), {party});
                INSERT INTO order_lines (id, order_id, line_no, material_id, grade_id, quantity, unit_id, quantity_kg)
                VALUES ({line}, {order}, 1, {material}, {grade}, 3, {unit}, 3000);
                """);
        }

        // 2) الإصدار الجديد.
        await using (var db = NewContext())
            await Initializer(db, "Bootstrap2026").InitializeAsync();

        // 3) الـ Grade باقٍ بلا شركة (لا تخمين) ومعتمد كما كان، والروابط كما هي.
        await using (var db = NewContext())
        {
            var g = await db.Grades.SingleAsync(x => x.Id == grade);
            Assert.Null(g.ManufacturerId);
            Assert.True(g.IsVerified);
            Assert.Equal("SG-5", g.Code);
            Assert.Equal(0, await db.Manufacturers.CountAsync());
            var i = await db.CustomerInterests.SingleAsync(x => x.Id == interest);
            Assert.Equal(grade, i.GradeId);
            Assert.False(i.OpenSpec);
            Assert.Null(i.OriginCountryId);
            var l = await db.OrderLines.SingleAsync(x => x.Id == line);
            Assert.Equal(grade, l.GradeId);
            Assert.False(l.OpenSpec);
            Assert.Equal(3000, l.QuantityKg);
            Assert.True(await db.LookupItems.AnyAsync(x => x.Category == "country" && x.Code == "SA"));

            // نفس الكود مرة ثانية بشركة «غير محددة» مرفوض من قاعدة البيانات نفسها.
            db.Grades.Add(new Domain.Reference.Grade { MaterialId = material, Code = "SG 5", NormalizedCode = "SG5" });
            await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        }

        await using (var db = NewContext())
        {
            // ولشركة محددة مسموح، ومرتين لنفس الشركة مرفوض.
            var maker = new Domain.Reference.Manufacturer { Name = "شركة تجريبية", NormalizedName = "شركه تجريبيه" };
            db.Manufacturers.Add(maker);
            db.Grades.Add(new Domain.Reference.Grade { MaterialId = material, ManufacturerId = maker.Id, Code = "SG5", NormalizedCode = "SG5" });
            await db.SaveChangesAsync();
            db.Grades.Add(new Domain.Reference.Grade { MaterialId = material, ManufacturerId = maker.Id, Code = "sg-5", NormalizedCode = "SG5" });
            await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        }
    }
}
