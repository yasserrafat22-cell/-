using Qadisiyah.Api.Security;
using Qadisiyah.Application.Auth;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Api.Endpoints;

public static class AuthEndpoints
{
    public const string LoginRateLimit = "login";

    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("/api/v1/auth").WithTags("Auth");

        auth.MapPost("/login", async (LoginRequest request, AuthService service, HttpContext http, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrEmpty(request.Password)
                || request.DeviceId == Guid.Empty)
                return Problems.Validation("اسم المستخدم وكلمة المرور ومعرف الجهاز مطلوبة");

            var result = await service.LoginAsync(request, Ip(http), ct);
            return result.IsSuccess ? Results.Ok(result.Value) : Problems.Auth(result.Error!.Value, result.Detail);
        }).RequireRateLimiting(LoginRateLimit);

        auth.MapPost("/refresh", async (RefreshRequest request, AuthService service, HttpContext http, CancellationToken ct) =>
        {
            var result = await service.RefreshAsync(request, Ip(http), ct);
            return result.IsSuccess ? Results.Ok(result.Value) : Problems.Auth(result.Error!.Value, result.Detail);
        }).RequireRateLimiting(LoginRateLimit);

        auth.MapPost("/logout", async (LogoutRequest request, AuthService service, HttpContext http, CancellationToken ct) =>
        {
            Guid? userId = http.User.Identity?.IsAuthenticated == true ? http.User.UserId() : null;
            await service.LogoutAsync(request, userId, Ip(http), ct);
            return Results.NoContent();
        });

        // متاحة حتى لمن يجب عليه تغيير كلمة المرور.
        auth.MapGet("/me", async (HttpContext http, AuthService service, CancellationToken ct) =>
        {
            var info = await service.GetUserInfoAsync(http.User.UserId(), ct);
            return info is null ? Results.Unauthorized() : Results.Ok(info);
        }).RequireAuthorization();

        auth.MapPost("/change-password", async (
            ChangePasswordRequest request, HttpContext http, AuthService service, CancellationToken ct) =>
        {
            var result = await service.ChangePasswordAsync(
                http.User.UserId(), http.User.DeviceId(), request, Ip(http), ct);
            return result.IsSuccess ? Results.Ok(result.Value) : Problems.Auth(result.Error!.Value, result.Detail);
        }).RequireAuthorization();

        var admin = app.MapGroup("/api/v1/admin").WithTags("Admin");

        admin.MapPost("/users/{id:guid}/reset-password", async (
            Guid id, HttpContext http, AuthService service, CancellationToken ct) =>
        {
            var result = await service.ResetPasswordAsync(http.User.UserId(), id, Ip(http), ct);
            return result.IsSuccess ? Results.Ok(result.Value) : Problems.Auth(result.Error!.Value);
        }).RequirePermission(Permissions.UsersManage);

        admin.MapPost("/devices/{id:guid}/revoke", async (
            Guid id, RevokeDeviceRequest? request, HttpContext http, AuthService service, CancellationToken ct) =>
        {
            var found = await service.RevokeDeviceAsync(http.User.UserId(), id, request?.Reason, Ip(http), ct);
            return found ? Results.NoContent() : Problems.Auth(AuthError.NotFound);
        }).RequirePermission(Permissions.DevicesManage);
    }

    public sealed record RevokeDeviceRequest(string? Reason);

    private static string? Ip(HttpContext http) => http.Connection.RemoteIpAddress?.ToString();
}
