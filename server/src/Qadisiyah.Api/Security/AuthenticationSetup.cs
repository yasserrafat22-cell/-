using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Security;

namespace Qadisiyah.Api.Security;

public static class AuthenticationSetup
{
    /// <summary>
    /// اسم سياسة لكل صلاحية: <c>RequireAuthorization(Permissions.UsersManage)</c>.
    /// المستخدم المطالب بتغيير كلمة المرور لا يمر من أي سياسة صلاحية.
    /// </summary>
    public static IServiceCollection AddAppAuthentication(this IServiceCollection services, JwtOptions jwt)
    {
        services
            .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(o =>
            {
                o.MapInboundClaims = false;
                o.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidIssuer = jwt.Issuer,
                    ValidAudience = jwt.Audience,
                    IssuerSigningKey = jwt.Key(),
                    ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                    ClockSkew = TimeSpan.FromSeconds(30),
                    NameClaimType = "unique_name",
                    RoleClaimType = ClaimTypes.Role,
                };
                o.Events = new JwtBearerEvents { OnTokenValidated = ValidateSessionAsync };
            });

        services.AddAuthorization(o =>
        {
            foreach (var permission in Permissions.All)
            {
                o.AddPolicy(permission, p => p
                    .RequireAuthenticatedUser()
                    .RequireClaim(AppClaims.Permission, permission)
                    .RequireAssertion(c => !c.User.HasClaim(AppClaims.MustChangePassword, "true")));
            }
        });
        return services;
    }

    /// <summary>
    /// رمز الدخول صالح توقيعًا لكنه يُرفض إذا أُلغي الجهاز، أو عُطل الحساب،
    /// أو تغيرت كلمة المرور بعد إصداره.
    /// </summary>
    private static async Task ValidateSessionAsync(TokenValidatedContext context)
    {
        var principal = context.Principal!;
        if (!Guid.TryParse(principal.FindFirstValue("sub"), out var userId)
            || !Guid.TryParse(principal.FindFirstValue(AppClaims.DeviceId), out var deviceId)
            || !Guid.TryParse(principal.FindFirstValue(AppClaims.SecurityStamp), out var stamp))
        {
            context.Fail("Malformed token.");
            return;
        }

        var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
        var ct = context.HttpContext.RequestAborted;
        var user = await db.Users.AsNoTracking()
            .Where(u => u.Id == userId)
            .Select(u => new { u.IsActive, u.SecurityStamp })
            .FirstOrDefaultAsync(ct);
        var deviceRevoked = await db.Devices.AsNoTracking()
            .AnyAsync(d => d.Id == deviceId && d.RevokedAt != null, ct);

        if (user is null || !user.IsActive || user.SecurityStamp != stamp || deviceRevoked)
            context.Fail("Session is no longer valid.");
    }

    public static Guid UserId(this ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue("sub")!);

    public static Guid DeviceId(this ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue(AppClaims.DeviceId)!);

    public static TBuilder RequirePermission<TBuilder>(this TBuilder builder, string permission)
        where TBuilder : IEndpointConventionBuilder =>
        builder.RequireAuthorization(new AuthorizeAttribute(permission));
}
