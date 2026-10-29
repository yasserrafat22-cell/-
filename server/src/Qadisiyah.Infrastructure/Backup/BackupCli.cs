using System.Formats.Tar;
using System.Security.Cryptography;
using System.Text.Json;

namespace Qadisiyah.Infrastructure.Backup;

/// <summary>
/// يحول نسخة التطبيق المشفرة (.qbk) إلى ملفين بنفس صيغة backup-trial.sh:
/// qadisiyah-STAMP.dump و attachments-STAMP.tar، لتُستعاد بـ restore-trial.sh
/// (الاستعادة نفسها تبقى خطوة يدوية مستقلة).
/// </summary>
public static class BackupCli
{
    public static async Task<int> DecryptAsync(string backupFile, string outputDir)
    {
        var password = Environment.GetEnvironmentVariable("QBK_PASSWORD");
        if (string.IsNullOrEmpty(password))
        {
            Console.Error.Write("كلمة مرور النسخة: ");
            password = Console.ReadLine();
        }
        if (string.IsNullOrEmpty(password))
        {
            Console.Error.WriteLine("لم تُدخل كلمة المرور.");
            return 2;
        }

        Directory.CreateDirectory(outputDir);
        var tarPath = Path.Combine(outputDir, $".decrypt-{Guid.NewGuid():N}.tar");
        try
        {
            await using (var input = File.OpenRead(backupFile))
            await using (var output = File.Create(tarPath))
                await BackupCrypto.DecryptAsync(input, output, password, CancellationToken.None);
        }
        catch (CryptographicException e)
        {
            File.Delete(tarPath);
            Console.Error.WriteLine(e.Message);
            return 1;
        }

        var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture);
        // لاحقة «-app» حتى لا تتطابق مع نسخة يأخذها restore-trial.sh في نفس الثانية.
        var dump = Path.Combine(outputDir, $"qadisiyah-{stamp}-app.dump");
        var attachments = Path.Combine(outputDir, $"attachments-{stamp}-app.tar");
        await using (var source = File.OpenRead(tarPath))
        await using (var reader = new TarReader(source))
        await using (var attachmentsFile = File.Create(attachments))
        await using (var attachmentsTar = new TarWriter(attachmentsFile, TarEntryFormat.Pax))
        {
            while (await reader.GetNextEntryAsync() is { } entry)
            {
                if (entry.Name == "manifest.json" && entry.DataStream is not null)
                {
                    var manifest = await JsonDocument.ParseAsync(entry.DataStream);
                    Console.WriteLine($"نسخة بتاريخ {manifest.RootElement.GetProperty("createdAt")}، " +
                        $"آخر ترحيل: {manifest.RootElement.GetProperty("migration")}");
                }
                else if (entry.Name == "database.dump" && entry.DataStream is not null)
                {
                    await using var file = File.Create(dump);
                    await entry.DataStream.CopyToAsync(file);
                }
                else if (entry.Name.StartsWith("attachments/", StringComparison.Ordinal)
                    && entry.EntryType == TarEntryType.RegularFile && entry.DataStream is not null)
                {
                    await attachmentsTar.WriteEntryAsync(new PaxTarEntry(TarEntryType.RegularFile,
                        "./" + entry.Name["attachments/".Length..]) { DataStream = entry.DataStream });
                }
            }
        }
        File.Delete(tarPath);
        if (!File.Exists(dump))
        {
            Console.Error.WriteLine("النسخة لا تحتوي قاعدة بيانات.");
            return 1;
        }
        Console.WriteLine(dump);
        Console.WriteLine(attachments);
        return 0;
    }
}
