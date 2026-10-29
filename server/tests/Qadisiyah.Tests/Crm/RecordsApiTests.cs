using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>موظفو الشركة، ملفات الـ Grade في الكتالوج، ومؤشرات التكرار غير الهاتف.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class RecordsApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";
    private static readonly byte[] Png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
    private static readonly byte[] Pdf = "%PDF-1.4\n%test\n"u8.ToArray();

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private async Task<HttpClient> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, role);
        return api.CreateClient((await api.LoginAsync(username, Password)).AccessToken);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Json))!;

    private static async Task<JsonElement> Body(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<ReferenceBundle> Reference(HttpClient client) =>
        await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));

    private static CreatePartyRequest Customer(ReferenceBundle refs, string name, string? email = null) =>
        new(Guid.CreateVersion7(), name, true, false, [new PhoneInput(UniquePhone())],
            CustomerActivityId: refs.ActivityTypes.First(a => a.Code == "factory").Id, Email: email);

    private static async Task<PartyDetail> Create(HttpClient client, CreatePartyRequest request)
    {
        var response = await Post(client, "/api/v1/parties", request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await Read<PartyDetail>(response);
    }

    private static Task<HttpResponseMessage> UploadGradeFile(HttpClient client, Guid gradeId, string kind, byte[] bytes,
        string name)
    {
        var file = new ByteArrayContent(bytes);
        file.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        return client.PostAsync($"/api/v1/catalog/grades/{gradeId}/files", new MultipartFormDataContent
        {
            { new StringContent(Guid.CreateVersion7().ToString()), "id" },
            { new StringContent(kind), "kind" },
            { file, "file", name },
        });
    }

    [Fact]
    public async Task Contacts_are_added_by_the_owner_and_edited_only_by_the_admin()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(rep);
        var party = await Create(rep, Customer(refs, $"عميل موظفين {Guid.NewGuid():N}"[..20], null)
            with { ConfirmSimilar = true });

        var first = await Read<ContactDto>(await Post(rep, $"/api/v1/parties/{party.Id}/contacts",
            new ContactInput(Guid.CreateVersion7(), "م. سامي حسن", "مدير المشتريات", "01112345678")));
        Assert.True(first.IsPrimary);
        Assert.Equal("+201112345678", first.Mobile);
        var second = await Read<ContactDto>(await Post(rep, $"/api/v1/parties/{party.Id}/contacts",
            new ContactInput(Guid.CreateVersion7(), "أ. منى", "محاسبة", IsPrimary: true)));
        Assert.False(second.IsPrimary);

        var bad = await Post(rep, $"/api/v1/parties/{party.Id}/contacts",
            new ContactInput(Guid.CreateVersion7(), "رقم خاطئ", Mobile: "0131234567"));
        Assert.Equal("party.invalid_phone", (await Body(bad)).GetProperty("code").GetString());

        var repEdit = await rep.PutAsJsonAsync($"/api/v1/contacts/{second.Id}",
            new ContactInput(second.Id, "أ. منى علي", IsPrimary: true, Version: second.Version), Json);
        Assert.Equal(HttpStatusCode.Forbidden, repEdit.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.DeleteAsync($"/api/v1/contacts/{second.Id}")).StatusCode);

        var adminEdit = await Read<ContactDto>(await admin.PutAsJsonAsync($"/api/v1/contacts/{second.Id}",
            new ContactInput(second.Id, "أ. منى علي", "محاسبة", IsPrimary: true, Version: second.Version), Json));
        Assert.True(adminEdit.IsPrimary);
        var list = await Read<List<ContactDto>>(await rep.GetAsync($"/api/v1/parties/{party.Id}/contacts"));
        Assert.Equal(["أ. منى علي", "م. سامي حسن"], list.Select(c => c.Name));
        Assert.Single(list, c => c.IsPrimary);

        // من لا يرى العميل لا يرى موظفيه.
        var other = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/api/v1/parties/{party.Id}/contacts")).StatusCode);
    }

    [Fact]
    public async Task Grade_photo_and_datasheet_belong_to_the_central_grade()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(rep);
        var maker = await Read<ManufacturerDto>(await Post(rep, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"مصنع {Guid.NewGuid():N}"[..18])));
        var grade = await Read<CatalogGradeDto>(await Post(rep, "/api/v1/catalog/grades",
            new CreateGradeRequest(refs.Materials.First(m => m.Code == "PP").Id, maker.Id, $"G{Guid.NewGuid():N}"[..10])));

        Assert.Equal("attachment.wrong_type", (await Body(await UploadGradeFile(rep, grade.Id, "dataSheet", Png, "a.png")))
            .GetProperty("code").GetString());
        Assert.Equal("attachment.wrong_type", (await Body(await UploadGradeFile(rep, grade.Id, "photo", Pdf, "a.pdf")))
            .GetProperty("code").GetString());

        Assert.Equal(HttpStatusCode.Created, (await UploadGradeFile(rep, grade.Id, "photo", Png, "pp.png")).StatusCode);
        var sheet = await Read<GradeFileDto>(await UploadGradeFile(rep, grade.Id, "dataSheet", Pdf, "PP datasheet.pdf"));
        Assert.Equal("application/pdf", sheet.ContentType);

        // الاستبدال بعد الحفظ للمدير فقط.
        Assert.Equal(HttpStatusCode.Forbidden, (await UploadGradeFile(rep, grade.Id, "photo", Png, "new.png")).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await UploadGradeFile(admin, grade.Id, "photo", Png, "new.png")).StatusCode);

        var grades = await Read<List<CatalogGradeDto>>(await admin.GetAsync($"/api/v1/catalog/grades?materialId={grade.MaterialId}"));
        var listed = grades.Single(g => g.Id == grade.Id);
        Assert.Equal(sheet.Id, listed.DataSheetFileId);
        Assert.NotNull(listed.PhotoFileId);
        // يظهر للجميع في الكتالوج الموحد (نفس بيانات اختيار الخامة).
        var inBundle = (await Reference(rep)).Materials.SelectMany(m => m.Grades).Single(g => g.Id == grade.Id);
        Assert.Equal(sheet.Id, inBundle.DataSheetFileId);
        Assert.Equal(listed.PhotoFileId, inBundle.PhotoFileId);

        var content = await rep.GetAsync($"/api/v1/catalog/grade-files/{sheet.Id}/content");
        Assert.Equal(HttpStatusCode.OK, content.StatusCode);
        Assert.Equal(Pdf, await content.Content.ReadAsByteArrayAsync());
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.DeleteAsync($"/api/v1/catalog/grade-files/{sheet.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.DeleteAsync($"/api/v1/catalog/grade-files/{sheet.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/catalog/grade-files/{sheet.Id}/content")).StatusCode);
    }

    [Fact]
    public async Task Similar_name_or_email_needs_confirmation()
    {
        var secretary = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(secretary);
        var unique = $"زهره{Random.Shared.Next(100000, 999999)}";
        var email = $"i{Guid.NewGuid():N}"[..12] + "@example.com";
        var first = await Create(secretary, Customer(refs, $"شركة {unique} للصناعات", email));

        // نفس الاسم بعد حذف «شركة/مصنع» واختلاف الهمزات والتاء المربوطة.
        var byName = await Post(secretary, "/api/v1/parties", Customer(refs, $"مصنع {unique}"));
        Assert.Equal(HttpStatusCode.Conflict, byName.StatusCode);
        var body = await Body(byName);
        Assert.Equal("party.similar", body.GetProperty("code").GetString());
        Assert.Equal(first.Id, body.GetProperty("data")[0].GetProperty("partyId").GetGuid());
        Assert.Contains("name", body.GetProperty("data")[0].GetProperty("reasons").EnumerateArray().Select(r => r.GetString()));

        var byEmail = await Post(secretary, "/api/v1/parties", Customer(refs, "اسم مختلف تماما", email.ToUpperInvariant()));
        Assert.Equal("party.similar", (await Body(byEmail)).GetProperty("code").GetString());

        // رقم موظف مسجل لدى شركة أخرى.
        var contactPhone = UniquePhone();
        await Post(secretary, $"/api/v1/parties/{first.Id}/contacts", new ContactInput(Guid.CreateVersion7(), "موظف", Mobile: contactPhone));
        var byContact = await Post(secretary, "/api/v1/parties", Customer(refs, "اسم ثالث مختلف") with
        {
            Phones = [new PhoneInput(contactPhone)],
        });
        Assert.Equal("party.similar", (await Body(byContact)).GetProperty("code").GetString());

        // بعد التأكيد يُحفظ.
        Assert.Equal(HttpStatusCode.Created, (await Post(secretary, "/api/v1/parties",
            Customer(refs, $"مصنع {unique}") with { ConfirmSimilar = true })).StatusCode);

        // المندوب لا يرى السجل المشابه: رسالة عامة دون بيانات.
        var rep = await ClientAs(SystemRoles.Representative);
        var hidden = await Post(rep, "/api/v1/parties", Customer(await Reference(rep), $"{unique}"));
        var hiddenBody = await Body(hidden);
        Assert.Equal("party.similar_hidden", hiddenBody.GetProperty("code").GetString());
        Assert.DoesNotContain(unique, hiddenBody.ToString());
    }
}
