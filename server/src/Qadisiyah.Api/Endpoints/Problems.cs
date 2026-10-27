using Qadisiyah.Application.Auth;

namespace Qadisiyah.Api.Endpoints;

/// <summary>
/// كل الأخطاء ترجع بصيغة ProblemDetails مع حقل <c>code</c> ثابت يعتمد عليه
/// التطبيق، ورسالة عربية في <c>detail</c>.
/// </summary>
public static class Problems
{
    public static IResult Auth(AuthError error, string? detail = null)
    {
        var (status, message) = error switch
        {
            AuthError.InvalidCredentials => (StatusCodes.Status401Unauthorized, "اسم المستخدم أو كلمة المرور غير صحيحة"),
            AuthError.Locked => (StatusCodes.Status423Locked, "تم إيقاف الدخول مؤقتًا بسبب محاولات متكررة"),
            AuthError.Disabled => (StatusCodes.Status403Forbidden, "هذا الحساب غير مفعّل"),
            AuthError.DeviceRevoked => (StatusCodes.Status403Forbidden, "تم إلغاء صلاحية هذا الجهاز"),
            AuthError.InvalidRefreshToken => (StatusCodes.Status401Unauthorized, "انتهت الجلسة"),
            AuthError.WeakPassword => (StatusCodes.Status400BadRequest, "كلمة المرور غير مقبولة"),
            AuthError.NotFound => (StatusCodes.Status404NotFound, "العنصر غير موجود"),
            _ => (StatusCodes.Status400BadRequest, "طلب غير صالح"),
        };
        return Results.Problem(
            statusCode: status,
            detail: detail ?? message,
            extensions: new Dictionary<string, object?> { ["code"] = error.Code() });
    }

    public static IResult Validation(string detail) => Results.Problem(
        statusCode: StatusCodes.Status400BadRequest,
        detail: detail,
        extensions: new Dictionary<string, object?> { ["code"] = "validation" });
}
