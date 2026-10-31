using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>الإدخال السريع من Excel: المعاينة، تنفيذ الصفوف السليمة فقط، عدم التكرار، والاستكمال دون تعديل.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class ImportApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private static string Marker() => Random.Shared.Next(100000, 999999).ToString(CultureInfo.InvariantCulture);

    private async Task<HttpClient> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, role);
        return api.CreateClient((await api.LoginAsync(username, Password)).AccessToken);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Json))!;

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static Task<HttpResponseMessage> Upload(HttpClient client, string kind, string action, byte[] file,
        Guid? importId = null, Dictionary<string, int>? mapping = null)
    {
        var form = new MultipartFormDataContent { { new ByteArrayContent(file), "file", "data.xlsx" } };
        if (importId is { } id)
            form.Add(new StringContent(id.ToString()), "importId");
        if (mapping is not null)
            form.Add(new StringContent(JsonSerializer.Serialize(mapping)), "mapping");
        return client.PostAsync($"/api/v1/import/{kind}/{action}", form);
    }

    private static byte[] Sheet(string[] headers, params string[][] rows) =>
        XlsxWriter.Write("بيانات", headers, rows.Select(r => (IReadOnlyList<object?>)r.Cast<object?>().ToList()));

    private static async Task<(Guid Pp, string G1, string G2)> TwoGrades(HttpClient admin, string marker)
    {
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        var maker = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"مصنع {marker}")));
        var (g1, g2) = ($"IM{marker}A", $"IM{marker}B");
        foreach (var code in new[] { g1, g2 })
            Assert.Equal(HttpStatusCode.Created,
                (await Post(admin, "/api/v1/catalog/grades", new CreateGradeRequest(pp, maker.Id, code))).StatusCode);
        return (pp, g1, g2);
    }

    [Fact]
    public async Task Party_import_previews_imports_valid_rows_once_and_merges_same_company()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var office = await ClientAs(SystemRoles.Secretary);
        var m = Marker();
        var (_, g1, g2) = await TwoGrades(admin, m);
        var existingPhone = UniquePhone();
        var existing = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), $"قائم {m}", true, false, [new PhoneInput(existingPhone)], Interests: ApiFactory.FixtureInterests,
            ConfirmSimilar: true)));
        var (p1, p2, p3) = (UniquePhone(), UniquePhone(), UniquePhone());

        // عناوين غير قياسية يتعرف عليها الاستيراد، وعمود زائد يُتجاهل.
        var file = Sheet(["ملاحظة", "اسم الشركة", "رقم الموبايل", "Grade", "النوع"],
            ["", $"شركة أ {m}", p1, g1, "عميل"],
            ["", $"شركة أ {m}", "", g2, "عميل"],
            ["", "", p2, g1, ""],
            ["", $"شركة ب {m}", "12", "", "مورد"],
            ["", $"شركة ج {m}", "", "", ""],
            ["", $"قائم {m}", existingPhone, g1, "عميل"],
            ["", $"شركة د {m}", UniquePhone(), "", "شريك"],
            ["", $"شركة هـ {m}", p3, $"NOPE{m}", "مورد"]);

        var preview = await Read<ImportResult>(await Upload(office, "parties", "preview", file));
        Assert.Equal(new ImportCounts(New: 3, Existing: 1, Duplicate: 1, Invalid: 1, Review: 2), preview.Counts);
        Assert.Equal(1, preview.Mapping["name"]);
        Assert.Equal(2, preview.Mapping["phone"]);
        Assert.Contains(preview.Rows.Single(r => r.Row == 4).Notes, n => n.Contains("غير مصنف", StringComparison.Ordinal));
        Assert.Contains(preview.Rows.Single(r => r.Row == 9).Notes, n => n.Contains("غير موجود في الكتالوج", StringComparison.Ordinal));
        Assert.Null(preview.PreviousImportAt);
        // المعاينة لا تكتب شيئًا.
        Assert.Equal(0, (await Registry(office, $"q=شركة أ {m}")).Total);

        var importId = Guid.CreateVersion7();
        var commitResponse = await Upload(office, "parties", "commit", file, importId);
        Assert.True(commitResponse.IsSuccessStatusCode, await commitResponse.Content.ReadAsStringAsync());
        var done = await Read<ImportResult>(commitResponse);
        Assert.True(done.Committed);
        Assert.Equal(preview.Counts, done.Counts);

        // نفس الشركة من صفين ← بطاقة واحدة بالـ Grades الاثنين.
        var a = (await Registry(office, $"q=شركة أ {m}")).Items.Single();
        var detail = (await office.GetFromJsonAsync<PartyDetail>($"/api/v1/parties/{a.Id}", Json))!;
        Assert.Equal(new[] { g1, g2 }, detail.Interests.Select(i => i.GradeCode ?? "").Order().ToArray());
        var withExisting = (await office.GetFromJsonAsync<PartyDetail>($"/api/v1/parties/{existing.Id}", Json))!;
        Assert.Contains(withExisting.Interests, i => i.GradeCode == g1);
        Assert.Equal(0, (await Registry(office, $"q=شركة ب {m}")).Total);

        // إعادة الإرسال بنفس المعرف لا تكرر.
        var again = await Read<ImportResult>(await Upload(office, "parties", "commit", file, importId));
        Assert.Equal(done.Counts, again.Counts);
        Assert.Single((await Registry(office, $"q=شركة أ {m}")).Items);

        // نفس الملف بعملية جديدة: تنبيه بالاستيراد السابق، وكل الشركات موجودة.
        var second = await Read<ImportResult>(await Upload(office, "parties", "preview", file));
        Assert.NotNull(second.PreviousImportAt);
        Assert.Equal(0, second.Counts.New);

        // غير المصنف بلا اسم يظهر في «يحتاج استكمال» ويُستكمل بملء الفارغ فقط.
        var incomplete = await Registry(office, "role=incomplete&q=" + p2[1..]);
        var pending = incomplete.Items.Single();
        var unclassified = (await office.GetFromJsonAsync<PartyDetail>($"/api/v1/parties/{pending.Id}", Json))!;
        Assert.True(unclassified.NameMissing);
        Assert.Equal(g1, unclassified.PendingGrade);
        Assert.True(unclassified.CanComplete);
        var completed = await Read<PartyDetail>(await Post(office, $"/api/v1/parties/{pending.Id}/complete",
            new CompleteRequest(Name: $"شركة مستكملة {m}", IsCustomer: true)));
        Assert.False(completed.NameMissing);
        Assert.True(completed.IsCustomer);
        Assert.Contains(completed.Interests, i => i.GradeCode == g1);
        Assert.False(completed.CanComplete);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(office, $"/api/v1/parties/{pending.Id}/complete",
            new CompleteRequest(Name: "اسم آخر"))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(office, $"/api/v1/parties/{existing.Id}/complete",
            new CompleteRequest(Name: "اسم آخر"))).StatusCode);
    }

    private static async Task<PagedResult<RegistryItem>> Registry(HttpClient client, string query) =>
        (await client.GetFromJsonAsync<PagedResult<RegistryItem>>("/api/v1/parties?" + query, Json))!;

    [Fact]
    public async Task Import_never_reveals_hidden_companies_and_reps_cannot_import()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var purchasing = await ClientAs(SystemRoles.PurchasingManager);
        var rep = await ClientAs(SystemRoles.Representative);
        var m = Marker();
        var phone = UniquePhone();
        await Post(admin, "/api/v1/parties", new CreatePartyRequest(Guid.CreateVersion7(), $"عميل سري {m}", true, false,
            [new PhoneInput(phone)], Interests: ApiFactory.FixtureInterests, ConfirmSimilar: true));

        var file = Sheet(["الاسم", "الهاتف", "النوع"], [$"اسم مختلف {m}", phone, "عميل"]);
        var preview = await Read<ImportResult>(await Upload(purchasing, "parties", "preview", file));
        var row = preview.Rows.Single();
        Assert.Equal(ImportRowStatus.Review, row.Status);
        Assert.DoesNotContain(row.Notes, n => n.Contains("سري", StringComparison.Ordinal));

        Assert.Equal(HttpStatusCode.Forbidden, (await Upload(rep, "parties", "preview", file)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.GetAsync("/api/v1/import/templates/parties")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.GetAsync("/api/v1/export/catalog")).StatusCode);
    }

    [Fact]
    public async Task Catalog_import_reuses_existing_allows_same_code_other_maker_and_flags_ambiguous_rows()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var m = Marker();
        var (maker1, maker2, code) = ($"صانع {m}", $"صانع آخر {m}", $"CT{m}");
        var file = Sheet(["الخامة", "الشركة المصنعة", "Grade", "بلد الصنع"],
            ["PP", maker1, code, "السعودية"],
            ["بولي بروبلين", maker1, code, ""],
            ["PP", maker2, code, ""],
            ["PP", "", "G9", ""],
            ["خامة غريبة جدا", maker1, "X1", ""],
            ["PP", maker1, code + "Z", "بلد وهمي"]);

        var preview = await Read<ImportResult>(await Upload(admin, "catalog", "preview", file));
        Assert.Equal(new ImportCounts(New: 3, Existing: 0, Duplicate: 1, Invalid: 0, Review: 2), preview.Counts);
        Assert.Contains(preview.Rows.Single(r => r.Row == 4).Notes, n => n.Contains("لشركة أخرى", StringComparison.Ordinal));
        Assert.Contains(preview.Rows.Single(r => r.Row == 7).Notes, n => n.Contains("بلد الصنع", StringComparison.Ordinal));

        var done = await Read<ImportResult>(await Upload(admin, "catalog", "commit", file, Guid.CreateVersion7()));
        Assert.Equal(preview.Counts, done.Counts);
        var again = await Read<ImportResult>(await Upload(admin, "catalog", "preview", file));
        Assert.Equal(0, again.Counts.New);

        var grades = (await admin.GetFromJsonAsync<List<CatalogGradeDto>>("/api/v1/catalog/grades", Json))!;
        Assert.Equal(2, grades.Count(g => g.Code == code));
        var export = await admin.GetAsync("/api/v1/export/catalog");
        Assert.Equal(HttpStatusCode.OK, export.StatusCode);
        var rows = XlsxReader.Read(await export.Content.ReadAsStreamAsync());
        Assert.Equal(2, rows.Count(r => r[2] == code));
        Assert.Contains(rows, r => r[2] == code && r[3] == "السعودية");

        var template = await admin.GetAsync("/api/v1/import/templates/catalog");
        Assert.Equal(["الخامة", "الشركة المصنعة", "Grade", "بلد الصنع"],
            XlsxReader.Read(await template.Content.ReadAsStreamAsync())[0]);
    }
}
