using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>المرفقات: الأنواع والحدود، ربط TDS بالـ Grade الصحيح، والصلاحيات.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class AttachmentApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static readonly byte[] Png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5];
    private static readonly byte[] Pdf = "%PDF-1.4\n%test\n"u8.ToArray();

    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private async Task<HttpClient> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, role);
        var session = await api.LoginAsync(username, Password);
        return api.CreateClient(session.AccessToken);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Json))!;

    private static async Task<string?> Code(HttpResponseMessage response)
    {
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.TryGetProperty("code", out var c) ? c.GetString() : null;
    }

    private static async Task<PartyDetail> Party(HttpClient client, bool supplier) =>
        await Read<PartyDetail>(await client.PostAsJsonAsync("/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), supplier ? "مورد ملفات" : "عميل ملفات", !supplier, supplier,
            [new PhoneInput(UniquePhone())]), Json));

    private static Task<HttpResponseMessage> Upload(HttpClient client, Guid partyId, string kind, byte[] content,
        string name, Guid? gradeId = null, Guid? id = null)
    {
        var form = new MultipartFormDataContent
        {
            { new StringContent((id ?? Guid.CreateVersion7()).ToString()), "id" },
            { new StringContent(kind), "kind" },
        };
        if (gradeId is { } g)
            form.Add(new StringContent(g.ToString()), "gradeId");
        var file = new ByteArrayContent(content);
        file.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        form.Add(file, "file", name);
        return client.PostAsync($"/api/v1/parties/{partyId}/attachments", form);
    }

    private static async Task<CatalogGradeDto> Grade(HttpClient client, bool withManufacturer = true)
    {
        var refs = await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        if (!withManufacturer)
        {
            // Grade سابق بلا شركة (عبر كود نصي كما في النسخ السابقة).
            var p = await Read<PartyDetail>(await client.PostAsJsonAsync("/api/v1/parties", new CreatePartyRequest(
                Guid.CreateVersion7(), "عميل قديم", true, false, [new PhoneInput(UniquePhone())],
                Interests: [new InterestInput(pp, GradeCode: $"OLD{Guid.NewGuid():N}"[..12])]), Json));
            var gradeId = p.Interests[0].GradeId!.Value;
            return new CatalogGradeDto(gradeId, pp, "PP", "", null, null, [], null, false, true, null, null);
        }
        var maker = await Read<ManufacturerDto>(await client.PostAsJsonAsync("/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"مصنع {Guid.NewGuid():N}"[..14]), Json));
        return await Read<CatalogGradeDto>(await client.PostAsJsonAsync("/api/v1/catalog/grades",
            new CreateGradeRequest(pp, maker.Id, $"T{Guid.NewGuid():N}"[..10]), Json));
    }

    [Fact]
    public async Task Tds_is_stored_for_the_exact_grade_and_downloaded_privately()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var supplier = await Party(client, supplier: true);
        var grade = await Grade(client);

        var created = await Upload(client, supplier.Id, "technicalDataSheet", Pdf, "../../etc/TDS PP500.pdf", grade.Id);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var tds = await Read<AttachmentDto>(created);
        Assert.Equal("application/pdf", tds.ContentType);
        Assert.Equal("TDS PP500.pdf", tds.FileName);
        Assert.Equal(grade.Id, tds.GradeId);
        Assert.Equal(grade.MaterialId, tds.MaterialId);
        Assert.Equal(grade.ManufacturerName, tds.Spec!.ManufacturerName);

        var download = await client.GetAsync($"/api/v1/attachments/{tds.Id}/content");
        Assert.Equal(HttpStatusCode.OK, download.StatusCode);
        Assert.Equal("application/pdf", download.Content.Headers.ContentType!.MediaType);
        Assert.Contains("no-store", download.Headers.CacheControl!.ToString(), StringComparison.Ordinal);
        Assert.Equal(SHA256.HashData(Pdf), SHA256.HashData(await download.Content.ReadAsByteArrayAsync()));

        // بدون دخول: لا وصول.
        using var anonymous = api.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await anonymous.GetAsync($"/api/v1/attachments/{tds.Id}/content")).StatusCode);
    }

    [Fact]
    public async Task Tds_needs_a_grade_with_a_known_manufacturer_and_a_supplier()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var supplier = await Party(client, supplier: true);
        var customer = await Party(client, supplier: false);
        var grade = await Grade(client);
        var legacy = await Grade(client, withManufacturer: false);

        Assert.Equal("attachment.tds_needs_grade",
            await Code(await Upload(client, supplier.Id, "technicalDataSheet", Pdf, "a.pdf")));
        Assert.Equal("attachment.tds_needs_manufacturer",
            await Code(await Upload(client, supplier.Id, "technicalDataSheet", Pdf, "a.pdf", legacy.Id)));
        Assert.Equal("attachment.tds_supplier_only",
            await Code(await Upload(client, customer.Id, "technicalDataSheet", Pdf, "a.pdf", grade.Id)));
        Assert.Equal("attachment.wrong_type",
            await Code(await Upload(client, supplier.Id, "technicalDataSheet", Png, "a.pdf", grade.Id)));
    }

    [Fact]
    public async Task File_type_comes_from_content_and_size_is_limited()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var customer = await Party(client, supplier: false);

        Assert.Equal("attachment.unsupported",
            await Code(await Upload(client, customer.Id, "other", "MZ\x90\0 not really"u8.ToArray(), "photo.jpg")));
        var photo = await Read<AttachmentDto>(await Upload(client, customer.Id, "other", Png, "صورة.exe"));
        Assert.Equal("image/png", photo.ContentType);
        Assert.Equal("صورة.png", photo.FileName);

        var big = new byte[(int)AttachmentService.MaxImageBytes + 10];
        Png.CopyTo(big, 0);
        Assert.Equal("attachment.too_large", await Code(await Upload(client, customer.Id, "logo", big, "big.png")));
    }

    [Fact]
    public async Task A_new_logo_replaces_the_old_one_and_removal_is_soft()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var customer = await Party(client, supplier: false);
        var first = await Read<AttachmentDto>(await Upload(client, customer.Id, "logo", Png, "logo1.png"));
        var second = await Read<AttachmentDto>(await Upload(client, customer.Id, "logo", Png, "logo2.png"));

        var detail = await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{customer.Id}"));
        Assert.Equal(second.Id, detail.LogoAttachmentId);
        var list = await Read<List<AttachmentDto>>(await client.GetAsync($"/api/v1/parties/{customer.Id}/attachments"));
        Assert.DoesNotContain(list, a => a.Id == first.Id);

        Assert.Equal(HttpStatusCode.OK, (await client.DeleteAsync($"/api/v1/attachments/{second.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/v1/attachments/{second.Id}/content")).StatusCode);
        var history = await Read<List<HistoryItem>>(await client.GetAsync($"/api/v1/parties/{customer.Id}/history"));
        Assert.Contains(history, h => h.Description == "حذف الملف: logo2.png");
    }

    [Fact]
    public async Task Uploads_are_idempotent_and_need_edit_rights()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var customer = await Party(admin, supplier: false);
        var id = Guid.CreateVersion7();
        Assert.Equal(HttpStatusCode.Created, (await Upload(admin, customer.Id, "other", Pdf, "a.pdf", id: id)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Upload(admin, customer.Id, "other", Pdf, "a.pdf", id: id)).StatusCode);

        // من يرى العميل يرى ملفاته ويضيف إليها، والحذف للمدير العام فقط.
        var secretary = await ClientAs(SystemRoles.Secretary);
        Assert.Equal(HttpStatusCode.OK, (await secretary.GetAsync($"/api/v1/attachments/{id}/content")).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Upload(secretary, customer.Id, "other", Pdf, "b.pdf")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await secretary.DeleteAsync($"/api/v1/attachments/{id}")).StatusCode);

        // المندوب لا يرى عميلًا ليس له ولا ملفاته.
        var rep = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/attachments/{id}/content")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await Upload(rep, customer.Id, "other", Pdf, "c.pdf")).StatusCode);
    }
}
