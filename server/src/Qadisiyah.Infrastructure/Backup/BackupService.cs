using System.Diagnostics;
using System.Formats.Tar;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Npgsql;
using Qadisiyah.Application.Admin;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Storage;

namespace Qadisiyah.Infrastructure.Backup;

public sealed class BackupOptions
{
    public const string Section = "Backup";

    /// <summary>مسار pg_dump (إصدار يطابق خادم PostgreSQL أو أحدث منه بنفس الإصدار الرئيسي).</summary>
    public string PgDumpPath { get; set; } = "pg_dump";
}

/// <summary>
/// نسخة كاملة: pg_dump بصيغة custom (نفس صيغة سكربت backup-trial.sh) + ملفات المرفقات
/// + ملف وصف، في أرشيف tar مشفر بمفتاح عشوائي مغلف لمفتاح الجهاز المؤقت (كلمة مرور
/// المدير لا تصل للسيرفر). الملف المؤقت يُحذف بعد التنزيل.
/// </summary>
public sealed partial class BackupService(
    AppDbContext db,
    ICurrentUser user,
    TimeProvider clock,
    string connectionString,
    AttachmentOptions attachments,
    BackupOptions options,
    ILogger<BackupService> logger) : IBackupService
{
    private static readonly SemaphoreSlim OneAtATime = new(1, 1);

    public async Task<Result<BackupArchive>> CreateAsync(string devicePublicKey, CancellationToken ct)
    {
        if (!user.Has(Permissions.BackupManage))
            return AppError.Forbidden("النسخ الاحتياطي الكامل للمدير العام فقط");
        byte[] publicKey;
        try
        {
            publicKey = Convert.FromBase64String(devicePublicKey ?? "");
            using var _ = BackupCrypto.ImportPublicKey(publicKey);
        }
        catch (Exception e) when (e is FormatException or System.Security.Cryptography.CryptographicException)
        {
            return AppError.Validation("مفتاح الجهاز غير صالح؛ حدّث التطبيق", "backup.invalid_key");
        }
        if (!await OneAtATime.WaitAsync(0, ct))
            return AppError.Conflict("backup.busy", "توجد نسخة احتياطية قيد الإنشاء الآن. حاول بعد قليل");

        var work = Directory.CreateTempSubdirectory("qbk-");
        try
        {
            var stamp = clock.GetUtcNow().ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture);
            var dump = Path.Combine(work.FullName, "database.dump");
            var error = await DumpAsync(dump, ct);
            if (error is not null)
                return error;

            var tarPath = Path.Combine(work.FullName, "backup.tar");
            var files = 0;
            await using (var tarFile = File.Create(tarPath))
            await using (var tar = new TarWriter(tarFile, TarEntryFormat.Pax, leaveOpen: false))
            {
                var migration = (await db.Database.GetAppliedMigrationsAsync(ct)).LastOrDefault();
                var manifest = JsonSerializer.SerializeToUtf8Bytes(new
                {
                    format = 1,
                    createdAt = clock.GetUtcNow(),
                    migration,
                    database = "database.dump",
                    attachments = "attachments/",
                });
                await tar.WriteEntryAsync(new PaxTarEntry(TarEntryType.RegularFile, "manifest.json")
                {
                    DataStream = new MemoryStream(manifest),
                }, ct);
                await tar.WriteEntryAsync(dump, "database.dump", ct);
                if (Directory.Exists(attachments.Root))
                {
                    foreach (var file in Directory.EnumerateFiles(attachments.Root, "*", SearchOption.AllDirectories))
                    {
                        var relative = Path.GetRelativePath(attachments.Root, file).Replace('\\', '/');
                        await tar.WriteEntryAsync(file, "attachments/" + relative, ct);
                        files++;
                    }
                }
            }
            File.Delete(dump);

            var outPath = Path.Combine(work.FullName, "backup.qbk");
            await using (var plain = File.OpenRead(tarPath))
            await using (var encrypted = File.Create(outPath))
                await BackupCrypto.EncryptForDeviceAsync(plain, encrypted, publicKey, ct);
            File.Delete(tarPath);

            var length = new FileInfo(outPath).Length;
            db.Audit(user, clock, "backup.created", "backup", Guid.Empty, new { size = length, attachments = files });
            await db.SaveChangesAsync(ct);

            // الملف والمجلد المؤقت يُحذفان عند إغلاق التنزيل.
            var stream = new FileStream(outPath, FileMode.Open, FileAccess.Read, FileShare.Delete, 81920,
                FileOptions.DeleteOnClose | FileOptions.Asynchronous);
            var cleanup = work;
            work = null;
            return new BackupArchive(new CleanupStream(stream, cleanup), $"qadisiyah-{stamp}.qbkw", length);
        }
        finally
        {
            work?.Delete(recursive: true);
            OneAtATime.Release();
        }
    }

    private async Task<AppError?> DumpAsync(string target, CancellationToken ct)
    {
        var cs = new NpgsqlConnectionStringBuilder(connectionString);
        var start = new ProcessStartInfo(options.PgDumpPath)
        {
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (var arg in new[]
                 {
                     "--format=custom", "--file", target, "--host", cs.Host ?? "localhost", "--port", cs.Port.ToString(System.Globalization.CultureInfo.InvariantCulture),
                     "--username", cs.Username ?? "", "--dbname", cs.Database ?? "",
                 })
            start.ArgumentList.Add(arg);
        start.Environment["PGPASSWORD"] = cs.Password ?? "";
        try
        {
            using var process = Process.Start(start)!;
            var stderr = await process.StandardError.ReadToEndAsync(ct);
            await process.WaitForExitAsync(ct);
            if (process.ExitCode == 0 && new FileInfo(target).Length > 0)
                return null;
            DumpFailed(logger, process.ExitCode, stderr);
        }
        catch (System.ComponentModel.Win32Exception e)
        {
            DumpMissing(logger, e, options.PgDumpPath);
        }
        return AppError.Validation("تعذر إنشاء نسخة قاعدة البيانات على السيرفر. راجع سجل السيرفر", "backup.dump_failed");
    }

    [LoggerMessage(Level = LogLevel.Error, Message = "pg_dump failed ({Code}): {Error}")]
    private static partial void DumpFailed(ILogger logger, int code, string error);

    [LoggerMessage(Level = LogLevel.Error, Message = "pg_dump is not available at {Path}")]
    private static partial void DumpMissing(ILogger logger, Exception e, string path);

    /// <summary>يحذف المجلد المؤقت بعد انتهاء التنزيل.</summary>
    private sealed class CleanupStream(Stream inner, DirectoryInfo folder) : Stream
    {
        public override bool CanRead => true;
        public override bool CanSeek => inner.CanSeek;
        public override bool CanWrite => false;
        public override long Length => inner.Length;

        public override long Position
        {
            get => inner.Position;
            set => inner.Position = value;
        }

        public override int Read(byte[] buffer, int offset, int count) => inner.Read(buffer, offset, count);

        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct = default) =>
            inner.ReadAsync(buffer, ct);

        public override long Seek(long offset, SeekOrigin origin) => inner.Seek(offset, origin);
        public override void Flush() { }
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                inner.Dispose();
                try
                {
                    folder.Delete(recursive: true);
                }
                catch (IOException)
                {
                }
            }
            base.Dispose(disposing);
        }
    }
}
