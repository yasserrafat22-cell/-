using System.Security.Claims;
using Qadisiyah.Application.Common;
using Qadisiyah.Infrastructure.Security;

namespace Qadisiyah.Api.Security;

/// <summary>
/// المستخدم الحالي من رمز الدخول. المستخدم المطالب بتغيير كلمة المرور لا
/// يملك أي صلاحية حتى يغيرها.
/// </summary>
public sealed class HttpCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private ClaimsPrincipal Principal =>
        accessor.HttpContext?.User ?? throw new InvalidOperationException("No HTTP context.");

    public Guid UserId => Principal.UserId();

    public Guid DeviceId => Principal.DeviceId();

    public bool Has(string permission) =>
        !Principal.HasClaim(AppClaims.MustChangePassword, "true")
        && Principal.HasClaim(AppClaims.Permission, permission);
}
