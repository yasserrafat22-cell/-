using Qadisiyah.Application.Common;

namespace Qadisiyah.Application.Admin;

/// <summary>ملف نسخة احتياطية جاهز للتنزيل (يُحذف من السيرفر بعد إغلاقه).</summary>
public sealed record BackupArchive(Stream Content, string FileName, long Length);

public sealed record CreateBackupRequest(string Password);

/// <summary>نسخة كاملة مشفرة (قاعدة البيانات + المرفقات) يطلبها المدير من التطبيق.</summary>
public interface IBackupService
{
    Task<Result<BackupArchive>> CreateAsync(string password, CancellationToken ct);
}
