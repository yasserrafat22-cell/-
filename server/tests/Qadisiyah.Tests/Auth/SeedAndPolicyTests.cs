using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Qadisiyah.Application.Auth;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Auth;

[Collection(DatabaseCollection.Name)]
public sealed class SeedTests(ApiFactory api)
{
    [Fact]
    public async Task Four_approved_roles_are_seeded()
    {
        var roles = await api.WithDbAsync(db => db.Roles.OrderBy(r => r.Code).Select(r => r.Code).ToListAsync());

        Assert.Equal(
            [SystemRoles.PurchasingManager, SystemRoles.Representative, SystemRoles.SalesManager, SystemRoles.SystemAdmin],
            roles);
    }

    [Fact]
    public async Task Representative_has_no_sensitive_permissions_by_default()
    {
        var permissions = await api.WithDbAsync(db => db.RolePermissions
            .Where(rp => db.Roles.Any(r => r.Id == rp.RoleId && r.Code == SystemRoles.Representative))
            .Select(rp => rp.Permission).ToListAsync());

        Assert.DoesNotContain(Permissions.PricesView, permissions);
        Assert.DoesNotContain(Permissions.ProfitsView, permissions);
        Assert.DoesNotContain(Permissions.UsersManage, permissions);
        Assert.DoesNotContain(Permissions.ImportRun, permissions);
        Assert.Contains(Permissions.CustomersCreate, permissions);
    }

    [Fact]
    public async Task Reseeding_keeps_permissions_edited_by_the_admin()
    {
        await api.WithDbAsync(async db =>
        {
            var role = await db.Roles.SingleAsync(r => r.Code == SystemRoles.SalesManager);
            await db.RolePermissions
                .Where(rp => rp.RoleId == role.Id && rp.Permission == Permissions.ProfitsView)
                .ExecuteDeleteAsync();
        });

        using (var scope = api.Services.CreateScope())
            await scope.ServiceProvider.GetRequiredService<DbInitializer>().InitializeAsync();

        var (roleCount, hasProfits) = await api.WithDbAsync(async db => (
            await db.Roles.CountAsync(),
            await db.RolePermissions.AnyAsync(rp =>
                rp.Permission == Permissions.ProfitsView
                && db.Roles.Any(r => r.Id == rp.RoleId && r.Code == SystemRoles.SalesManager))));
        Assert.Equal(4, roleCount);
        Assert.False(hasProfits);
    }
}

public sealed class PasswordPolicyTests
{
    [Theory]
    [InlineData("short1", false)]
    [InlineData("onlyletters", false)]
    [InlineData("12345678", false)]
    [InlineData("Valid2026", true)]
    [InlineData("كلمةمرور2026", true)]
    public void Validate(string password, bool valid) =>
        Assert.Equal(valid, PasswordPolicy.Validate(password) is null);

    [Fact]
    public void Temporary_passwords_are_valid_and_unique()
    {
        var generated = Enumerable.Range(0, 50).Select(_ => PasswordPolicy.GenerateTemporary()).ToList();

        Assert.All(generated, p => Assert.Null(PasswordPolicy.Validate(p)));
        Assert.Equal(generated.Count, generated.Distinct().Count());
    }
}
