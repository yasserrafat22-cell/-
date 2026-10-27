using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Auth;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Auth;

[Collection(DatabaseCollection.Name)]
public sealed class AuthApiTests(ApiFactory api)
{
    private const string Password = "Rep12345a";

    private static async Task<string?> ErrorCode(HttpResponseMessage response)
    {
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return json.RootElement.TryGetProperty("code", out var code) ? code.GetString() : null;
    }

    private static string Unique(string prefix) => $"{prefix}_{Guid.NewGuid():N}"[..20];

    private static Task<HttpResponseMessage> PostLogin(HttpClient client, string username, string password, Guid deviceId) =>
        client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(username, password, deviceId, "test"));

    [Fact]
    public async Task Bootstrap_admin_must_change_password_before_using_permissions()
    {
        var session = await api.LoginAsync("admin", ApiFactory.AdminPassword);

        Assert.True(session.User.MustChangePassword);
        Assert.Contains(SystemRoles.SystemAdmin, session.User.Roles);

        using var client = api.CreateClient(session.AccessToken);
        var blocked = await client.PostAsync($"/api/v1/admin/devices/{Guid.NewGuid()}/revoke", null);
        Assert.Equal(HttpStatusCode.Forbidden, blocked.StatusCode);

        var me = await client.GetAsync("/api/v1/auth/me");
        Assert.Equal(HttpStatusCode.OK, me.StatusCode);
    }

    [Fact]
    public async Task Wrong_password_and_unknown_user_return_the_same_error()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        using var client = api.CreateClient();

        var wrong = await PostLogin(client, username, "Wrong12345", Guid.NewGuid());
        var unknown = await PostLogin(client, "no_such_user", "Wrong12345", Guid.NewGuid());

        Assert.Equal(HttpStatusCode.Unauthorized, wrong.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, unknown.StatusCode);
        Assert.Equal("auth.invalid_credentials", await ErrorCode(wrong));
        Assert.Equal("auth.invalid_credentials", await ErrorCode(unknown));
    }

    [Fact]
    public async Task Account_locks_after_repeated_failures_even_with_correct_password()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        using var client = api.CreateClient();

        for (var i = 0; i < 5; i++)
            await PostLogin(client, username, "Wrong12345", Guid.NewGuid());
        var locked = await PostLogin(client, username, Password, Guid.NewGuid());

        Assert.Equal(HttpStatusCode.Locked, locked.StatusCode);
        Assert.Equal("auth.locked", await ErrorCode(locked));
    }

    [Fact]
    public async Task Disabled_user_cannot_log_in()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative, active: false);
        using var client = api.CreateClient();

        var response = await PostLogin(client, username, Password, Guid.NewGuid());

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal("auth.disabled", await ErrorCode(response));
    }

    [Fact]
    public async Task Passwords_are_stored_only_as_hashes()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);

        var hash = await api.WithDbAsync(db => db.Users.Where(u => u.Username == username)
            .Select(u => u.PasswordHash).SingleAsync());

        Assert.DoesNotContain(Password, hash, StringComparison.Ordinal);
        Assert.True(hash.Length > 60);
    }

    [Fact]
    public async Task Refresh_rotates_and_reusing_an_old_token_revokes_the_session()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        var deviceId = Guid.CreateVersion7();
        var first = await api.LoginAsync(username, Password, deviceId);
        using var client = api.CreateClient();

        var rotated = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken, deviceId));
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        var second = (await rotated.Content.ReadFromJsonAsync<AuthResponse>())!;
        Assert.NotEqual(first.RefreshToken, second.RefreshToken);

        var reuse = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken, deviceId));
        Assert.Equal(HttpStatusCode.Unauthorized, reuse.StatusCode);

        // إعادة الاستخدام تُلغي العائلة كلها، فيسقط حتى الرمز الأحدث.
        var afterReuse = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(second.RefreshToken, deviceId));
        Assert.Equal(HttpStatusCode.Unauthorized, afterReuse.StatusCode);
        Assert.Equal("auth.invalid_refresh_token", await ErrorCode(afterReuse));
    }

    [Fact]
    public async Task Refresh_token_is_bound_to_its_device()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        var session = await api.LoginAsync(username, Password);
        using var client = api.CreateClient();

        var response = await client.PostAsJsonAsync("/api/v1/auth/refresh",
            new RefreshRequest(session.RefreshToken, Guid.CreateVersion7()));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Logout_revokes_the_refresh_token()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        var deviceId = Guid.CreateVersion7();
        var session = await api.LoginAsync(username, Password, deviceId);
        using var client = api.CreateClient();

        var logout = await client.PostAsJsonAsync("/api/v1/auth/logout", new LogoutRequest(session.RefreshToken));
        var refresh = await client.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(session.RefreshToken, deviceId));

        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);
    }

    [Fact]
    public async Task Changing_password_invalidates_previous_tokens_and_sessions()
    {
        var username = Unique("rep");
        await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        var deviceId = Guid.CreateVersion7();
        var otherDevice = Guid.CreateVersion7();
        var session = await api.LoginAsync(username, Password, deviceId);
        var otherSession = await api.LoginAsync(username, Password, otherDevice);
        using var client = api.CreateClient(session.AccessToken);

        var weak = await client.PostAsJsonAsync("/api/v1/auth/change-password",
            new ChangePasswordRequest(Password, "short"));
        Assert.Equal(HttpStatusCode.BadRequest, weak.StatusCode);
        Assert.Equal("auth.weak_password", await ErrorCode(weak));

        var changed = await client.PostAsJsonAsync("/api/v1/auth/change-password",
            new ChangePasswordRequest(Password, "Changed2026x"));
        Assert.Equal(HttpStatusCode.OK, changed.StatusCode);

        var oldToken = await client.GetAsync("/api/v1/auth/me");
        Assert.Equal(HttpStatusCode.Unauthorized, oldToken.StatusCode);

        using var anonymous = api.CreateClient();
        var otherRefresh = await anonymous.PostAsJsonAsync("/api/v1/auth/refresh",
            new RefreshRequest(otherSession.RefreshToken, otherDevice));
        Assert.Equal(HttpStatusCode.Unauthorized, otherRefresh.StatusCode);

        var relogin = await PostLogin(anonymous, username, "Changed2026x", Guid.NewGuid());
        Assert.Equal(HttpStatusCode.OK, relogin.StatusCode);
    }

    [Fact]
    public async Task Representative_cannot_use_admin_endpoints()
    {
        var username = Unique("rep");
        var userId = await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        var session = await api.LoginAsync(username, Password);
        using var client = api.CreateClient(session.AccessToken);

        var reset = await client.PostAsync($"/api/v1/admin/users/{userId}/reset-password", null);
        var revoke = await client.PostAsync($"/api/v1/admin/devices/{Guid.NewGuid()}/revoke", null);
        using var anonymous = api.CreateClient();
        var noToken = await anonymous.PostAsync($"/api/v1/admin/users/{userId}/reset-password", null);

        Assert.Equal(HttpStatusCode.Forbidden, reset.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, revoke.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, noToken.StatusCode);
    }

    [Fact]
    public async Task Admin_reset_issues_a_temporary_password_that_must_be_changed()
    {
        var adminName = Unique("adm");
        await api.CreateUserAsync(adminName, Password, SystemRoles.SystemAdmin);
        var repName = Unique("rep");
        var repId = await api.CreateUserAsync(repName, Password, SystemRoles.Representative);
        var repDevice = Guid.CreateVersion7();
        var repSession = await api.LoginAsync(repName, Password, repDevice);
        var admin = await api.LoginAsync(adminName, Password);
        using var adminClient = api.CreateClient(admin.AccessToken);

        var reset = await adminClient.PostAsync($"/api/v1/admin/users/{repId}/reset-password", null);
        Assert.Equal(HttpStatusCode.OK, reset.StatusCode);
        var temporary = (await reset.Content.ReadFromJsonAsync<ResetPasswordResponse>())!.TemporaryPassword;
        Assert.Null(PasswordPolicy.Validate(temporary));

        using var anonymous = api.CreateClient();
        var oldPassword = await PostLogin(anonymous, repName, Password, Guid.NewGuid());
        Assert.Equal(HttpStatusCode.Unauthorized, oldPassword.StatusCode);
        var oldSession = await anonymous.PostAsJsonAsync("/api/v1/auth/refresh",
            new RefreshRequest(repSession.RefreshToken, repDevice));
        Assert.Equal(HttpStatusCode.Unauthorized, oldSession.StatusCode);

        var withTemporary = await api.LoginAsync(repName, temporary);
        Assert.True(withTemporary.User.MustChangePassword);

        var audited = await api.WithDbAsync(db =>
            db.AuditEntries.AnyAsync(a => a.Action == "users.password_reset" && a.EntityId == repId));
        Assert.True(audited);
    }

    [Fact]
    public async Task Revoked_device_is_locked_out_immediately()
    {
        var adminName = Unique("adm");
        await api.CreateUserAsync(adminName, Password, SystemRoles.SystemAdmin);
        var repName = Unique("rep");
        await api.CreateUserAsync(repName, Password, SystemRoles.Representative);
        var lostPhone = Guid.CreateVersion7();
        var repSession = await api.LoginAsync(repName, Password, lostPhone);
        var admin = await api.LoginAsync(adminName, Password);
        using var adminClient = api.CreateClient(admin.AccessToken);

        var revoke = await adminClient.PostAsJsonAsync($"/api/v1/admin/devices/{lostPhone}/revoke",
            new { reason = "هاتف مفقود" });
        Assert.Equal(HttpStatusCode.NoContent, revoke.StatusCode);

        using var repClient = api.CreateClient(repSession.AccessToken);
        Assert.Equal(HttpStatusCode.Unauthorized, (await repClient.GetAsync("/api/v1/auth/me")).StatusCode);

        using var anonymous = api.CreateClient();
        var refresh = await anonymous.PostAsJsonAsync("/api/v1/auth/refresh",
            new RefreshRequest(repSession.RefreshToken, lostPhone));
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);

        var login = await PostLogin(anonymous, repName, Password, lostPhone);
        Assert.Equal(HttpStatusCode.Forbidden, login.StatusCode);
        Assert.Equal("auth.device_revoked", await ErrorCode(login));

        var otherDevice = await PostLogin(anonymous, repName, Password, Guid.CreateVersion7());
        Assert.Equal(HttpStatusCode.OK, otherDevice.StatusCode);
    }

    [Fact]
    public async Task Login_is_audited()
    {
        var username = Unique("rep");
        var userId = await api.CreateUserAsync(username, Password, SystemRoles.Representative);
        using var client = api.CreateClient();
        await PostLogin(client, username, "Wrong12345", Guid.NewGuid());
        await api.LoginAsync(username, Password);

        var actions = await api.WithDbAsync(db => db.AuditEntries
            .Where(a => a.UserId == userId).OrderBy(a => a.At).Select(a => a.Action).ToListAsync());

        Assert.Equal(["auth.login_failed", "auth.login"], actions);
    }
}
