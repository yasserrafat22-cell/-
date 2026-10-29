using Qadisiyah.Application.Common;

namespace Qadisiyah.Application.Admin;

/// <summary>ملف نسخة احتياطية جاهز للتنزيل (يُحذف من السيرفر بعد إغلاقه).</summary>
public sealed record BackupArchive(Stream Content, string FileName, long Length);

/// <summary>
/// المفتاح العام المؤقت للجهاز (Base64 لنقطة P-256 غير مضغوطة، 65 بايت). كلمة مرور النسخة
/// لا تُرسل للسيرفر إطلاقًا: التطبيق يغلّف مفتاح النسخة بها على الجهاز.
/// </summary>
public sealed record CreateBackupRequest(string PublicKey);

/// <summary>نسخة كاملة مشفرة (قاعدة البيانات + المرفقات) يطلبها المدير من التطبيق.</summary>
public interface IBackupService
{
    Task<Result<BackupArchive>> CreateAsync(string devicePublicKey, CancellationToken ct);
}
