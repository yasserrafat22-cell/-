namespace Qadisiyah.Application.Common;

/// <summary>تخزين محتوى المرفقات. المفتاح يولده السيرفر فقط (لا مسارات من المستخدم).</summary>
public interface IFileStore
{
    /// <summary>يحفظ المحتوى كاملًا أو لا شيء (ملف مؤقت ثم نقل).</summary>
    Task SaveAsync(string key, Stream content, CancellationToken ct);

    /// <summary>null إذا كان الملف غير موجود.</summary>
    Stream? OpenRead(string key);
}
