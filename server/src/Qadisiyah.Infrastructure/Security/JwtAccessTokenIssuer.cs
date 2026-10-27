using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Qadisiyah.Application;
using Qadisiyah.Application.Auth;

namespace Qadisiyah.Infrastructure.Security;

public sealed class JwtOptions
{
    public const string Section = "Jwt";

    /// <summary>
    /// مفتاح يُستخدم في بيئة التطوير فقط. السيرفر يرفض العمل به خارج Development.
    /// </summary>
    public const string DevelopmentSigningKey = "qadisiyah-development-only-signing-key-do-not-use-in-production";

    public string Issuer { get; set; } = "qadisiyah";
    public string Audience { get; set; } = "qadisiyah-app";
    public string SigningKey { get; set; } = "";

    public SymmetricSecurityKey Key() => new(Encoding.UTF8.GetBytes(SigningKey));
}

public static class AppClaims
{
    public const string DeviceId = "sid";
    public const string SecurityStamp = "stamp";
    public const string Permission = "perm";
    public const string MustChangePassword = "pwd_change";
}

public sealed class JwtAccessTokenIssuer(JwtOptions jwt, AuthOptions auth, TimeProvider clock) : IAccessTokenIssuer
{
    private readonly JsonWebTokenHandler handler = new();

    public (string Token, DateTimeOffset ExpiresAt) Issue(AccessTokenClaims claims)
    {
        var now = clock.GetUtcNow();
        var expires = now + auth.AccessTokenLifetime;

        var subject = new ClaimsIdentity(
        [
            new Claim(JwtRegisteredClaimNames.Sub, claims.UserId.ToString()),
            new Claim(JwtRegisteredClaimNames.UniqueName, claims.Username),
            new Claim(AppClaims.DeviceId, claims.DeviceId.ToString()),
            new Claim(AppClaims.SecurityStamp, claims.SecurityStamp.ToString()),
        ]);
        if (claims.MustChangePassword)
            subject.AddClaim(new Claim(AppClaims.MustChangePassword, "true"));
        foreach (var role in claims.Roles)
            subject.AddClaim(new Claim(ClaimTypes.Role, role));
        foreach (var permission in claims.Permissions)
            subject.AddClaim(new Claim(AppClaims.Permission, permission));

        var token = handler.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = jwt.Issuer,
            Audience = jwt.Audience,
            Subject = subject,
            IssuedAt = now.UtcDateTime,
            NotBefore = now.UtcDateTime,
            Expires = expires.UtcDateTime,
            SigningCredentials = new SigningCredentials(jwt.Key(), SecurityAlgorithms.HmacSha256),
        });
        return (token, expires);
    }
}
