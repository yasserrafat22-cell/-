using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Auth;

/// <summary>
/// الدخول والجلسات وكلمات المرور. كل الفحوص هنا على السيرفر؛ التطبيق لا يُعتمد
/// عليه في أي قرار أمني.
/// </summary>
public sealed class AuthService(
    IAppDbContext db,
    IPasswordHasher hasher,
    IAccessTokenIssuer tokens,
    AuthOptions options,
    TimeProvider clock)
{
    // يُستخدم عند عدم وجود المستخدم حتى يستغرق الرد نفس الوقت تقريبًا
    // فلا يمكن تمييز الأسماء الموجودة من زمن الاستجابة.
    private static string? dummyHash;

    private string DummyHash => dummyHash ??= hasher.Hash("dummy-password-1");

    public async Task<AuthResult<AuthResponse>> LoginAsync(LoginRequest request, string? ip, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var username = User.NormalizeUsername(request.Username);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Username == username, ct);

        if (user is null)
        {
            hasher.Verify(DummyHash, request.Password);
            await AuditAsync("auth.login_failed", null, request.DeviceId, ip, new { username, reason = "unknown_user" }, ct);
            return AuthResult.Fail<AuthResponse>(AuthError.InvalidCredentials);
        }

        if (user.LockoutEndsAt > now)
        {
            await AuditAsync("auth.login_failed", user.Id, request.DeviceId, ip, new { reason = "locked" }, ct);
            return AuthResult.Fail<AuthResponse>(AuthError.Locked);
        }

        if (!hasher.Verify(user.PasswordHash, request.Password))
        {
            user.FailedLoginCount++;
            var locked = user.FailedLoginCount >= options.MaxFailedAttempts;
            if (locked)
            {
                user.LockoutEndsAt = now + options.LockoutDuration;
                user.FailedLoginCount = 0;
            }
            await AuditAsync("auth.login_failed", user.Id, request.DeviceId, ip,
                new { reason = "wrong_password", locked }, ct);
            return AuthResult.Fail<AuthResponse>(AuthError.InvalidCredentials);
        }

        // حالة الحساب تُفحص بعد التحقق من كلمة المرور حتى لا تكشف وجود الحساب.
        if (!user.IsActive)
        {
            await AuditAsync("auth.login_failed", user.Id, request.DeviceId, ip, new { reason = "disabled" }, ct);
            return AuthResult.Fail<AuthResponse>(AuthError.Disabled);
        }

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == request.DeviceId, ct);
        if (device is { IsRevoked: true })
        {
            await AuditAsync("auth.login_failed", user.Id, request.DeviceId, ip, new { reason = "device_revoked" }, ct);
            return AuthResult.Fail<AuthResponse>(AuthError.DeviceRevoked);
        }

        if (device is null)
        {
            device = new Device { Id = request.DeviceId, Name = DeviceName(request.DeviceName), FirstSeenAt = now };
            db.Devices.Add(device);
        }
        device.Name = DeviceName(request.DeviceName);
        device.LastSeenAt = now;
        device.LastUserId = user.Id;

        user.FailedLoginCount = 0;
        user.LockoutEndsAt = null;
        user.LastLoginAt = now;
        user.UpdatedAt = now;

        var response = await IssueSessionAsync(user, device.Id, Guid.CreateVersion7(), ct);
        await AuditAsync("auth.login", user.Id, device.Id, ip, null, ct);
        return response;
    }

    public async Task<AuthResult<AuthResponse>> RefreshAsync(RefreshRequest request, string? ip, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var hash = HashToken(request.RefreshToken);
        var token = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (token is null || token.DeviceId != request.DeviceId)
            return AuthResult.Fail<AuthResponse>(AuthError.InvalidRefreshToken);

        if (token.ConsumedAt is not null || token.RevokedAt is not null)
        {
            if (token.ConsumedAt is not null)
            {
                // رمز مستهلك يُعاد استخدامه: احتمال سرقة، فتُلغى الجلسة بالكامل.
                await RevokeFamilyAsync(token.FamilyId, now, ct);
                await AuditAsync("auth.refresh_reuse_detected", token.UserId, token.DeviceId, ip, null, ct);
            }
            return AuthResult.Fail<AuthResponse>(AuthError.InvalidRefreshToken);
        }

        if (token.ExpiresAt <= now)
            return AuthResult.Fail<AuthResponse>(AuthError.InvalidRefreshToken);

        var device = await db.Devices.FirstAsync(d => d.Id == token.DeviceId, ct);
        if (device.IsRevoked)
            return AuthResult.Fail<AuthResponse>(AuthError.DeviceRevoked);

        var user = await db.Users.FirstAsync(u => u.Id == token.UserId, ct);
        if (!user.IsActive)
            return AuthResult.Fail<AuthResponse>(AuthError.Disabled);

        token.ConsumedAt = now;
        device.LastSeenAt = now;
        try
        {
            return await IssueSessionAsync(user, device.Id, token.FamilyId, ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            // طلبا تحديث متزامنان بنفس الرمز: ينجح أحدهما فقط.
            return AuthResult.Fail<AuthResponse>(AuthError.InvalidRefreshToken);
        }
    }

    public async Task LogoutAsync(LogoutRequest request, Guid? userId, string? ip, CancellationToken ct)
    {
        var hash = HashToken(request.RefreshToken);
        var token = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (token is null)
            return;
        await RevokeFamilyAsync(token.FamilyId, clock.GetUtcNow(), ct);
        await AuditAsync("auth.logout", userId ?? token.UserId, token.DeviceId, ip, null, ct);
    }

    public async Task<UserInfo?> GetUserInfoAsync(Guid userId, CancellationToken ct)
    {
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId, ct);
        if (user is null)
            return null;
        var (roles, permissions) = await LoadAccessAsync(user.Id, ct);
        return ToInfo(user, roles, permissions);
    }

    /// <summary>
    /// تغيير كلمة المرور يُبطل كل الجلسات الأخرى ويعيد جلسة جديدة لهذا الجهاز.
    /// </summary>
    public async Task<AuthResult<AuthResponse>> ChangePasswordAsync(
        Guid userId, Guid deviceId, ChangePasswordRequest request, string? ip, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var user = await db.Users.FirstAsync(u => u.Id == userId, ct);
        if (user.LockoutEndsAt > now)
            return AuthResult.Fail<AuthResponse>(AuthError.Locked);

        // محاولات خاطئة لكلمة المرور الحالية تُحتسب ضمن قفل الحساب، حتى لا يمكن
        // تخمينها بجلسة مسروقة.
        if (!hasher.Verify(user.PasswordHash, request.CurrentPassword))
        {
            user.FailedLoginCount++;
            var locked = user.FailedLoginCount >= options.MaxFailedAttempts;
            if (locked)
            {
                user.LockoutEndsAt = now + options.LockoutDuration;
                user.FailedLoginCount = 0;
            }
            await AuditAsync("auth.change_password_failed", user.Id, deviceId, ip, new { locked }, ct);
            return AuthResult.Fail<AuthResponse>(locked ? AuthError.Locked : AuthError.WrongCurrentPassword);
        }

        var weakness = PasswordPolicy.Validate(request.NewPassword);
        if (weakness is not null)
            return AuthResult.Fail<AuthResponse>(AuthError.WeakPassword, weakness);
        if (request.NewPassword == request.CurrentPassword)
            return AuthResult.Fail<AuthResponse>(AuthError.WeakPassword, "كلمة المرور الجديدة يجب أن تختلف عن الحالية");

        user.PasswordHash = hasher.Hash(request.NewPassword);
        user.MustChangePassword = false;
        user.FailedLoginCount = 0;
        user.SecurityStamp = Guid.NewGuid();
        user.UpdatedAt = now;
        await RevokeUserSessionsAsync(user.Id, now, ct);

        var response = await IssueSessionAsync(user, deviceId, Guid.CreateVersion7(), ct);
        await AuditAsync("auth.password_changed", user.Id, deviceId, ip, null, ct);
        return response;
    }

    /// <summary>
    /// إعادة تعيين من مدير النظام (قرار السؤال 3): كلمة مرور مؤقتة تُعرض مرة واحدة
    /// مع إجبار المستخدم على تغييرها.
    /// </summary>
    public async Task<AuthResult<ResetPasswordResponse>> ResetPasswordAsync(
        Guid adminId, Guid targetUserId, string? ip, CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == targetUserId, ct);
        if (user is null)
            return AuthResult.Fail<ResetPasswordResponse>(AuthError.NotFound);

        var now = clock.GetUtcNow();
        var temporary = PasswordPolicy.GenerateTemporary();
        user.PasswordHash = hasher.Hash(temporary);
        user.MustChangePassword = true;
        user.SecurityStamp = Guid.NewGuid();
        user.FailedLoginCount = 0;
        user.LockoutEndsAt = null;
        user.UpdatedAt = now;
        await RevokeUserSessionsAsync(user.Id, now, ct);

        db.AuditEntries.Add(NewAudit("users.password_reset", adminId, null, ip, "user", user.Id, null));
        await db.SaveChangesAsync(ct);
        return new ResetPasswordResponse(temporary);
    }

    public async Task<bool> RevokeDeviceAsync(Guid adminId, Guid deviceId, string? reason, string? ip, CancellationToken ct)
    {
        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == deviceId, ct);
        if (device is null)
            return false;

        var now = clock.GetUtcNow();
        device.RevokedAt ??= now;
        device.RevokedBy ??= adminId;
        device.RevokeReason = reason;
        await db.RefreshTokens
            .Where(t => t.DeviceId == deviceId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);

        db.AuditEntries.Add(NewAudit("devices.revoked", adminId, null, ip, "device", deviceId, new { reason }));
        await db.SaveChangesAsync(ct);
        return true;
    }

    private async Task<AuthResponse> IssueSessionAsync(User user, Guid deviceId, Guid familyId, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var (roles, permissions) = await LoadAccessAsync(user.Id, ct);

        var (accessToken, accessExpiresAt) = tokens.Issue(new AccessTokenClaims(
            user.Id, user.Username, deviceId, user.SecurityStamp, user.MustChangePassword, roles, permissions));

        var refreshToken = Base64Url(RandomNumberGenerator.GetBytes(32));
        var refresh = new RefreshToken
        {
            UserId = user.Id,
            DeviceId = deviceId,
            FamilyId = familyId,
            TokenHash = HashToken(refreshToken),
            CreatedAt = now,
            ExpiresAt = now + options.RefreshTokenLifetime,
        };
        db.RefreshTokens.Add(refresh);
        await db.SaveChangesAsync(ct);

        return new AuthResponse(accessToken, accessExpiresAt, refreshToken, refresh.ExpiresAt,
            ToInfo(user, roles, permissions));
    }

    private async Task<(string[] Roles, string[] Permissions)> LoadAccessAsync(Guid userId, CancellationToken ct)
    {
        var roleIds = db.UserRoles.Where(ur => ur.UserId == userId).Select(ur => ur.RoleId);
        var roles = await db.Roles.Where(r => roleIds.Contains(r.Id)).Select(r => r.Code).OrderBy(c => c).ToArrayAsync(ct);
        var permissions = await db.RolePermissions
            .Where(rp => roleIds.Contains(rp.RoleId))
            .Select(rp => rp.Permission)
            .Distinct()
            .OrderBy(p => p)
            .ToArrayAsync(ct);
        return (roles, permissions);
    }

    private Task<int> RevokeFamilyAsync(Guid familyId, DateTimeOffset now, CancellationToken ct) =>
        db.RefreshTokens
            .Where(t => t.FamilyId == familyId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);

    private Task<int> RevokeUserSessionsAsync(Guid userId, DateTimeOffset now, CancellationToken ct) =>
        db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);

    private async Task AuditAsync(string action, Guid? userId, Guid? deviceId, string? ip, object? data, CancellationToken ct)
    {
        db.AuditEntries.Add(NewAudit(action, userId, deviceId, ip, null, null, data));
        await db.SaveChangesAsync(ct);
    }

    private AuditEntry NewAudit(string action, Guid? userId, Guid? deviceId, string? ip,
        string? entityType, Guid? entityId, object? data) => new()
        {
            At = clock.GetUtcNow(),
            Action = action,
            UserId = userId,
            DeviceId = deviceId,
            IpAddress = ip,
            EntityType = entityType,
            EntityId = entityId,
            Data = data is null ? null : JsonSerializer.Serialize(data),
        };

    private static UserInfo ToInfo(User user, string[] roles, string[] permissions) =>
        new(user.Id, user.Username, user.DisplayName, roles, permissions, user.MustChangePassword);

    private static string DeviceName(string? name) =>
        string.IsNullOrWhiteSpace(name) ? "unknown" : name.Trim()[..Math.Min(name.Trim().Length, 100)];

    internal static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
