namespace Qadisiyah.Application.Auth;

public sealed record LoginRequest(string Username, string Password, Guid DeviceId, string? DeviceName);

public sealed record RefreshRequest(string RefreshToken, Guid DeviceId);

public sealed record LogoutRequest(string RefreshToken);

public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);

public sealed record UserInfo(
    Guid Id,
    string Username,
    string DisplayName,
    IReadOnlyCollection<string> Roles,
    IReadOnlyCollection<string> Permissions,
    bool MustChangePassword);

public sealed record AuthResponse(
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt,
    UserInfo User);

public sealed record ResetPasswordResponse(string TemporaryPassword);

/// <summary>
/// أخطاء المصادقة. الكود يُرسل للتطبيق ضمن ProblemDetails ليعرض رسالة مناسبة.
/// </summary>
public enum AuthError
{
    InvalidCredentials,
    Locked,
    Disabled,
    DeviceRevoked,
    InvalidRefreshToken,
    WeakPassword,
    WrongCurrentPassword,
    NotFound,
}

public static class AuthErrorCodes
{
    public static string Code(this AuthError error) => error switch
    {
        AuthError.InvalidCredentials => "auth.invalid_credentials",
        AuthError.Locked => "auth.locked",
        AuthError.Disabled => "auth.disabled",
        AuthError.DeviceRevoked => "auth.device_revoked",
        AuthError.InvalidRefreshToken => "auth.invalid_refresh_token",
        AuthError.WeakPassword => "auth.weak_password",
        AuthError.WrongCurrentPassword => "auth.wrong_current_password",
        AuthError.NotFound => "not_found",
        _ => throw new ArgumentOutOfRangeException(nameof(error), error, null),
    };
}

/// <summary>نتيجة عملية: قيمة عند النجاح أو خطأ مع تفاصيل اختيارية.</summary>
public readonly record struct AuthResult<T>(T? Value, AuthError? Error, string? Detail = null)
{
    public bool IsSuccess => Error is null;

    public static implicit operator AuthResult<T>(T value) => new(value, null);
}

public static class AuthResult
{
    public static AuthResult<T> Fail<T>(AuthError error, string? detail = null) => new(default, error, detail);
}

public sealed class AuthOptions
{
    public const string Section = "Auth";

    public TimeSpan AccessTokenLifetime { get; set; } = TimeSpan.FromMinutes(15);
    public TimeSpan RefreshTokenLifetime { get; set; } = TimeSpan.FromDays(30);
    public int MaxFailedAttempts { get; set; } = 5;
    public TimeSpan LockoutDuration { get; set; } = TimeSpan.FromMinutes(15);
}
