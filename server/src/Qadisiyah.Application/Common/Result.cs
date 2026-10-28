namespace Qadisiyah.Application.Common;

public enum ErrorKind
{
    Validation,
    NotFound,
    Forbidden,
    Conflict,
}

/// <summary>
/// خطأ عملية: كود ثابت يعتمد عليه التطبيق، ورسالة عربية للمستخدم، وبيانات
/// اختيارية (مثل الطرف الموجود عند تكرار رقم الهاتف).
/// </summary>
public sealed record AppError(ErrorKind Kind, string Code, string Message, object? Data = null)
{
    public static AppError Validation(string message, string code = "validation") => new(ErrorKind.Validation, code, message);
    public static AppError NotFound(string message = "العنصر غير موجود") => new(ErrorKind.NotFound, "not_found", message);
    public static AppError Forbidden(string message = "ليست لديك صلاحية لهذه العملية") => new(ErrorKind.Forbidden, "forbidden", message);
    public static AppError Conflict(string code, string message, object? data = null) => new(ErrorKind.Conflict, code, message, data);

    /// <summary>السجل عُدّل من جهاز آخر بعد قراءته؛ لا يُستبدل تعديل الآخر بصمت.</summary>
    public static AppError StaleVersion() => Conflict(
        "concurrency.stale",
        "تم تعديل هذا السجل من مستخدم آخر. حدّث البيانات ثم أعد المحاولة.");
}

public readonly record struct Result<T>(T? Value, AppError? Error)
{
    public bool IsSuccess => Error is null;

    public static implicit operator Result<T>(T value) => new(value, null);

    public static implicit operator Result<T>(AppError error) => new(default, error);
}

public interface ICurrentUser
{
    Guid UserId { get; }
    Guid DeviceId { get; }
    bool Has(string permission);
}
