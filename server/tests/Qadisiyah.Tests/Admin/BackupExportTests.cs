using System.Formats.Tar;
using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Admin;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Infrastructure.Backup;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Admin;

[Collection(DatabaseCollection.Name)]
public sealed class BackupExportTests(ApiFactory api)
{
    private const string Password = "Crm12345a";
    private const string BackupPassword = "كلمة-سر-النسخة-2026";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private async Task<HttpClient> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, role);
        return api.CreateClient((await api.LoginAsync(username, Password)).AccessToken);
    }

    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private static async Task<PartyDetail> Customer(HttpClient client, string name)
    {
        var refs = (await client.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var response = await client.PostAsJsonAsync("/api/v1/parties", new CreatePartyRequest(Guid.CreateVersion7(), name,
            true, false, [new PhoneInput(UniquePhone())],
            CustomerActivityId: refs.ActivityTypes.First(a => a.Code == "factory").Id, ConfirmSimilar: true), Json);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<PartyDetail>(Json))!;
    }

    [Theory]
    [InlineData(0)]
    [InlineData(10)]
    [InlineData(3 * 1024 * 1024 + 17)]
    public async Task Encryption_round_trips_and_rejects_wrong_password_or_tampering(int size)
    {
        var plain = RandomNumberGenerator.GetBytes(size);
        using var encrypted = new MemoryStream();
        await BackupCrypto.EncryptAsync(new MemoryStream(plain), encrypted, BackupPassword, default);
        var bytes = encrypted.ToArray();
        Assert.False(size > 64 && bytes.AsSpan().IndexOf(plain.AsSpan(0, 64)) >= 0);

        using var decrypted = new MemoryStream();
        await BackupCrypto.DecryptAsync(new MemoryStream(bytes), decrypted, BackupPassword, default);
        Assert.Equal(plain, decrypted.ToArray());

        await Assert.ThrowsAsync<CryptographicException>(() =>
            BackupCrypto.DecryptAsync(new MemoryStream(bytes), Stream.Null, "كلمة-خاطئة-تماما", default));
        // ملف مقصوص (حذف آخر جزء) أو معدل لا يُقبل.
        await Assert.ThrowsAsync<CryptographicException>(() =>
            BackupCrypto.DecryptAsync(new MemoryStream(bytes[..^20]), Stream.Null, BackupPassword, default));
        var tampered = bytes.ToArray();
        tampered[^20] ^= 1;
        await Assert.ThrowsAsync<CryptographicException>(() =>
            BackupCrypto.DecryptAsync(new MemoryStream(tampered), Stream.Null, BackupPassword, default));
    }

    [Fact]
    public async Task Admin_downloads_a_full_encrypted_backup_that_decrypts_for_restore()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var party = await Customer(admin, "عميل النسخة الاحتياطية");
        var logo = new ByteArrayContent([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9, 9]);
        logo.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        var attachmentId = Guid.CreateVersion7();
        Assert.Equal(HttpStatusCode.Created, (await admin.PostAsync($"/api/v1/parties/{party.Id}/attachments",
            new MultipartFormDataContent
            {
                { new StringContent(attachmentId.ToString()), "id" },
                { new StringContent("logo"), "kind" },
                { logo, "file", "logo.png" },
            })).StatusCode);

        var response = await admin.PostAsJsonAsync("/api/v1/admin/backups", new CreateBackupRequest(BackupPassword), Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.EndsWith(".qbk", response.Content.Headers.ContentDisposition?.FileNameStar ?? response.Content.Headers.ContentDisposition?.FileName?.Trim('"'));
        var file = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal("QBK1"u8.ToArray(), file[..4]);
        Assert.True(file.AsSpan().IndexOf("عميل النسخة"u8) < 0);

        var work = Directory.CreateTempSubdirectory("qbk-test-");
        try
        {
            var qbk = Path.Combine(work.FullName, "b.qbk");
            await File.WriteAllBytesAsync(qbk, file);
            Environment.SetEnvironmentVariable("QBK_PASSWORD", BackupPassword);
            Assert.Equal(0, await BackupCli.DecryptAsync(qbk, work.FullName));
            var dump = Directory.GetFiles(work.FullName, "qadisiyah-*.dump").Single();
            Assert.Equal("PGDMP"u8.ToArray(), (await File.ReadAllBytesAsync(dump))[..5]);
            var tar = Directory.GetFiles(work.FullName, "attachments-*.tar").Single();
            var names = new List<string>();
            await using (var reader = new TarReader(File.OpenRead(tar)))
                while (await reader.GetNextEntryAsync() is { } entry)
                    names.Add(entry.Name);
            Assert.Contains(names, n => n.EndsWith(attachmentId.ToString("N"), StringComparison.Ordinal));

            Environment.SetEnvironmentVariable("QBK_PASSWORD", "كلمة-خاطئة-تماما");
            Assert.Equal(1, await BackupCli.DecryptAsync(qbk, Path.Combine(work.FullName, "wrong")));
        }
        finally
        {
            Environment.SetEnvironmentVariable("QBK_PASSWORD", null);
            work.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task Only_the_admin_backs_up_and_the_password_must_be_strong()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var weak = await admin.PostAsJsonAsync("/api/v1/admin/backups", new CreateBackupRequest("123"), Json);
        Assert.Equal(HttpStatusCode.BadRequest, weak.StatusCode);
        foreach (var role in new[] { SystemRoles.Secretary, SystemRoles.Representative, SystemRoles.SalesManager })
        {
            var client = await ClientAs(role);
            var response = await client.PostAsJsonAsync("/api/v1/admin/backups", new CreateBackupRequest(BackupPassword), Json);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
    }

    private static async Task<string> SheetText(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var zip = new ZipArchive(new MemoryStream(await response.Content.ReadAsByteArrayAsync()));
        using var reader = new StreamReader(zip.GetEntry("xl/worksheets/sheet1.xml")!.Open(), Encoding.UTF8);
        return await reader.ReadToEndAsync();
    }

    [Fact]
    public async Task Excel_export_follows_the_viewer_permissions()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var otherRep = await ClientAs(SystemRoles.Representative);
        var secretary = await ClientAs(SystemRoles.Secretary);
        var marker = Guid.NewGuid().ToString("N")[..6];
        await Customer(rep, $"عميلي {marker}");
        await Customer(otherRep, $"عميل غيري {marker}");
        await Customer(rep, $"=HYPERLINK(\"x\") {marker}");

        var mine = await SheetText(await rep.GetAsync("/api/v1/export/parties?role=customer"));
        Assert.Contains($"عميلي {marker}", mine);
        Assert.DoesNotContain($"عميل غيري {marker}", mine);
        // قيمة تبدأ بـ = لا تُنفذ كمعادلة عند فتح الملف.
        Assert.Contains("&apos;=HYPERLINK", mine);
        Assert.Contains("rightToLeft=\"1\"", mine);

        Assert.Equal(HttpStatusCode.Forbidden, (await rep.GetAsync("/api/v1/export/parties?role=supplier")).StatusCode);
        var all = await SheetText(await secretary.GetAsync("/api/v1/export/parties?role=customer"));
        Assert.True(all.Contains($"عميل غيري {marker}", StringComparison.Ordinal), all[..Math.Min(all.Length, 3000)]);
        Assert.Equal(HttpStatusCode.OK, (await secretary.GetAsync("/api/v1/export/parties?role=supplier")).StatusCode);
    }
}
