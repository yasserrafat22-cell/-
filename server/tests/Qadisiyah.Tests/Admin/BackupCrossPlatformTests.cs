using System.Text;
using Qadisiyah.Infrastructure.Backup;

namespace Qadisiyah.Tests.Admin;

/// <summary>
/// توافق صيغة النسخة بين السيرفر (.NET) والتطبيق (Dart): ملف QBKW أنشأه السيرفر لمفتاح جهاز
/// ثابت، فحوله التطبيق إلى QBK2 بكلمة مرور؛ يجب أن يفكه السيرفر (أداة الاستعادة) بنفس المحتوى.
/// </summary>
public sealed class BackupCrossPlatformTests
{
    public const string FixturePlain = "QADISIYAH BACKUP FIXTURE — نسخة اختبار";
    private const string DevicePublicKey =
        "BIPm+WOfZiMlVDisIMi6399JFyVFtjGCmEZiM/yV/4Y4oJbSIbViZ/bjZ0BTVEzXnIDKlVmT9WIzAVniotVNh0U=";

    private static string Fixtures => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
        "../../../../../../app/test/fixtures"));

    [Fact]
    public async Task File_wrapped_by_the_app_decrypts_with_the_restore_tool()
    {
        if (Environment.GetEnvironmentVariable("QBK_WRITE_FIXTURE") == "1")
        {
            await using var wire = File.Create(Path.Combine(Fixtures, "backup_wire.bin"));
            await BackupCrypto.EncryptForDeviceAsync(new MemoryStream(Encoding.UTF8.GetBytes(FixturePlain)), wire,
                Convert.FromBase64String(DevicePublicKey), default);
            return;
        }
        var fromApp = Path.Combine(Fixtures, "backup_from_app.qbk2");
        using var output = new MemoryStream();
        await BackupCrypto.DecryptAsync(File.OpenRead(fromApp), output, "App-Fixture-Password", default);
        Assert.Equal(FixturePlain, Encoding.UTF8.GetString(output.ToArray()));
    }
}
