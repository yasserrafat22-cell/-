using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>«الإدخال السريع»: لصق/Excel، بانتظار الاستكمال، التكرار، التراجع الآمن، والتصدير الذكي.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class QuickEntryApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string Mobile() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private static string Unique(string name) => $"{name} {Guid.NewGuid():N}"[..(name.Length + 9)];

    private async Task<HttpClient> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, role);
        return api.CreateClient((await api.LoginAsync(username, Password)).AccessToken);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response)
    {
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private static async Task<string?> Code(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.GetProperty("code").GetString();

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static QuickEntryRow Row(int n, string? name, string? phone, string? material, string? grade,
        string? kind = null, string? maker = null) =>
        new(Guid.CreateVersion7(), n, kind, name, phone, material, grade, maker);

    private static async Task<(string Material, string Grade, Guid GradeId, Guid MaterialId)> GradeAsync(HttpClient admin)
    {
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var pp = refs.Materials.First(m => m.Code == "PP");
        var maker = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"صانع {Guid.NewGuid():N}"[..16])));
        var code = $"Q{Guid.NewGuid():N}"[..8];
        var grade = await Read<CatalogGradeDto>(await Post(admin, "/api/v1/catalog/grades",
            new CreateGradeRequest(pp.Id, maker.Id, code)));
        return ("pp", code.ToLowerInvariant(), grade.Id, pp.Id);
    }

    [Fact]
    public async Task A_mixed_paste_creates_complete_rows_and_keeps_the_rest_pending()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var (material, grade, gradeId, _) = await GradeAsync(admin);
        var phone = Mobile();
        var existing = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), Unique("عميل قائم"), true, false, [new PhoneInput(Mobile())],
            Interests: ApiFactory.FixtureInterests)));
        var rows = new[]
        {
            Row(1, Unique("عميل كامل"), phone, material, grade, "عميل"),
            Row(2, Unique("مورد كامل"), "+20" + Mobile()[1..], "PP", grade.ToUpperInvariant(), "مورد"),
            Row(3, Unique("بلا جريد"), Mobile(), "PP", null, "عميل"),
            Row(4, Unique("رقم ناقص"), "0155566", "PP", grade, "عميل"),
            Row(5, Unique("بلا نوع"), Mobile(), "PP", grade, "شركة"),
            Row(6, Unique("نفس الرقم"), phone, "PP", grade, "عميل"),
            Row(7, Unique("رقم مسجل"), existing.Phones[0].E164, "PP", grade, "عميل"),
            // Excel يحذف الصفر الأول من الأرقام: 10 أرقام تبدأ بـ 1 تُوحد دون تخمين.
            Row(8, Unique("بلا صفر"), Mobile()[1..], "PP", grade, "عميل"),
        };
        var request = new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Mixed, rows);

        var preview = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/validate", request));
        Assert.False(preview.Committed);
        Assert.Equal(["ready", "ready", "pending", "pending", "pending", "duplicate", "duplicate", "ready"],
            preview.Rows.Select(r => r.Status));
        Assert.Contains(QuickEntryIssues.GradeMissing, preview.Rows[2].Issues);
        Assert.Contains(QuickEntryIssues.PhoneInvalid, preview.Rows[3].Issues);
        Assert.Contains(QuickEntryIssues.KindMissing, preview.Rows[4].Issues);
        Assert.Equal(existing.Id, preview.Rows[6].DuplicateOfId);

        var done = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", request));
        Assert.Equal(3, done.Created);
        Assert.Equal(3, done.Pending);
        Assert.Equal(2, done.Duplicate);
        var customer = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{rows[0].Id}"));
        Assert.True(customer.IsCustomer && !customer.IsSupplier);
        Assert.Equal(gradeId, customer.Interests.Single().GradeId);
        var supplier = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{rows[1].Id}"));
        Assert.True(supplier.IsSupplier && !supplier.IsCustomer);
        Assert.Equal(gradeId, supplier.Products.Single().GradeId);

        // المعلق ليس عميلًا ولا موردًا: لا يظهر في السجل.
        Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/v1/parties/{rows[2].Id}")).StatusCode);
        var registry = await Read<PagedResult<RegistryItem>>(
            await admin.GetAsync($"/api/v1/parties?q={Uri.EscapeDataString(rows[2].Name!)}"));
        Assert.Empty(registry.Items);

        // إعادة إرسال نفس الدفعة لا تكرر شيئًا.
        var again = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", request));
        Assert.Equal(done.Rows.Select(r => (r.Id, r.Status)), again.Rows.Select(r => (r.Id, r.Status)));
        var count = await Read<PagedResult<RegistryItem>>(
            await admin.GetAsync($"/api/v1/parties?q={Uri.EscapeDataString(rows[0].Name!)}"));
        Assert.Single(count.Items);
    }

    [Fact]
    public async Task A_pending_row_is_corrected_then_promoted_exactly_once()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var (_, grade, gradeId, materialId) = await GradeAsync(admin);
        var row = Row(1, Unique("عميل ناقص"), null, "PP", null);
        var batch = await Read<QuickBatchResult>(await Post(rep, "/api/v1/quick-entry/batches",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Customers, [row])));
        Assert.Equal(1, batch.Pending);

        var pending = await Read<PagedResult<PendingEntryDto>>(await rep.GetAsync("/api/v1/quick-entry/pending?take=200"));
        var entry = pending.Items.Single(p => p.Id == row.Id);
        Assert.Equal([QuickEntryIssues.PhoneMissing, QuickEntryIssues.GradeMissing], entry.Issues);
        Assert.Equal("quick.incomplete", await Code(await Post(rep, $"/api/v1/quick-entry/pending/{row.Id}/complete", new { })));

        // حفظ التقدم لا يُنشئ بطاقة.
        var saved = await Read<PendingEntryDto>(await rep.PutAsJsonAsync($"/api/v1/quick-entry/pending/{row.Id}",
            new PendingUpdate("customer", row.Name, Mobile(), null, null, MaterialId: materialId, GradeId: gradeId), Json));
        Assert.Empty(saved.Issues);
        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/parties/{row.Id}")).StatusCode);

        var first = await Read<CompletedEntry>(await Post(rep, $"/api/v1/quick-entry/pending/{row.Id}/complete", new { }));
        var second = await Read<CompletedEntry>(await Post(rep, $"/api/v1/quick-entry/pending/{row.Id}/complete", new { }));
        Assert.Equal(first.PartyId, second.PartyId);
        var party = await Read<PartyDetail>(await rep.GetAsync($"/api/v1/parties/{first.PartyId}"));
        Assert.Equal(gradeId, party.Interests.Single().GradeId);
        var after = await Read<PagedResult<PendingEntryDto>>(await rep.GetAsync("/api/v1/quick-entry/pending?take=200"));
        Assert.DoesNotContain(after.Items, p => p.Id == row.Id);

        // مندوب آخر لا يرى صفوف غيره.
        var other = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.NotFound,
            (await other.PutAsJsonAsync($"/api/v1/quick-entry/pending/{row.Id}", new PendingUpdate(null, "x", null, null, null), Json)).StatusCode);
    }

    [Fact]
    public async Task A_duplicate_adds_its_grade_to_the_existing_record_only_on_confirmation()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var (_, grade, gradeId, _) = await GradeAsync(admin);
        var original = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), Unique("عميل أصلي"), true, false, [new PhoneInput(Mobile())],
            Interests: ApiFactory.FixtureInterests)));
        var row = Row(1, "اسم مختلف تمامًا", original.Phones[0].E164, "PP", grade);
        var batch = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Customers, [row])));
        Assert.Equal("duplicate", batch.Rows.Single().Status);
        Assert.Equal(original.Id, batch.Rows.Single().DuplicateOfId);

        var merged = await Read<CompletedEntry>(await Post(admin, $"/api/v1/quick-entry/pending/{row.Id}/merge", new { }));
        Assert.Equal(original.Id, merged.PartyId);
        Assert.False(merged.Created);
        var party = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{original.Id}"));
        Assert.Equal(original.Name, party.Name); // الاسم الأصلي لا يتغير
        Assert.Contains(party.Interests, i => i.GradeId == gradeId);
        Assert.Equal(original.Interests.Count + 1, party.Interests.Count);

        // نفس الرقم لمورد: إضافة دور العميل تحتاج تأكيدًا صريحًا.
        var supplier = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), Unique("مورد قائم"), false, true, [new PhoneInput(Mobile())])));
        var row2 = Row(1, "عميل جديد", supplier.Phones[0].E164, "PP", grade);
        await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Customers, [row2])));
        Assert.Equal("quick.role_needed", await Code(await Post(admin, $"/api/v1/quick-entry/pending/{row2.Id}/merge", new { })));
        await Read<CompletedEntry>(await Post(admin, $"/api/v1/quick-entry/pending/{row2.Id}/merge", new { addRole = true }));
        var both = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{supplier.Id}"));
        Assert.True(both.IsCustomer && both.IsSupplier);
    }

    [Fact]
    public async Task A_grade_code_of_two_manufacturers_is_never_guessed()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        var code = $"A{Guid.NewGuid():N}"[..8];
        var makerA = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"صانع {Guid.NewGuid():N}"[..16])));
        var makerB = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"صانع {Guid.NewGuid():N}"[..16])));
        await Post(admin, "/api/v1/catalog/grades", new CreateGradeRequest(pp, makerA.Id, code));
        var b = await Read<CatalogGradeDto>(await Post(admin, "/api/v1/catalog/grades",
            new CreateGradeRequest(pp, makerB.Id, code, ConfirmSimilar: true)));

        var result = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/validate",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Customers,
            [
                Row(1, "عميل", Mobile(), "PP", code),
                Row(2, "عميل آخر", Mobile(), "PP", code, maker: makerB.Name),
                Row(3, "عميل ثالث", Mobile(), "PET", code),
            ])));
        Assert.Contains(QuickEntryIssues.GradeAmbiguous, result.Rows[0].Issues);
        Assert.Equal(b.Id, result.Rows[1].GradeId);
        Assert.Contains(QuickEntryIssues.GradeUnknown, result.Rows[2].Issues);
    }

    [Fact]
    public async Task Excel_files_list_every_sheet_with_a_suggested_mapping()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var file = XlsxWriter.WriteSheets([
            new XlsxSheet("ملاحظات", ["أي شيء"], [["نص"]]),
            new XlsxSheet("العملاء", ["رقم الموبايل", "اسم الشركة", "الخامة", "Grade"],
                [["01012345678", "شركة النور", "PP", "500P"]]),
        ]);
        HttpContent Form(string name)
        {
            var content = new ByteArrayContent(file);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            return new MultipartFormDataContent { { content, "file", name } };
        }

        Assert.Equal(HttpStatusCode.Forbidden, (await rep.PostAsync("/api/v1/quick-entry/excel/read", Form("a.xlsx"))).StatusCode);
        var sheets = await Read<List<ExcelSheet>>(await admin.PostAsync("/api/v1/quick-entry/excel/read", Form("a.xlsx")));
        Assert.Equal(["ملاحظات", "العملاء"], sheets.Select(s => s.Name));
        var data = sheets[1];
        // ترتيب الأعمدة لا يهم: كل حقل بعنوانه.
        Assert.Equal(0, data.Mapping["phone"]);
        Assert.Equal(1, data.Mapping["name"]);
        Assert.Equal(2, data.Mapping["material"]);
        Assert.Equal(3, data.Mapping["grade"]);
        Assert.Equal("01012345678", data.Rows[0][0]); // الصفر الأول محفوظ
        Assert.Equal("import.xls", await Code(await admin.PostAsync("/api/v1/quick-entry/excel/read", Form("old.xls"))));
    }

    [Fact]
    public async Task Export_uses_one_filtered_query_and_hides_suppliers_from_sales()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var (_, grade, gradeId, materialId) = await GradeAsync(admin);
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var otherMaterial = refs.Materials.First(m => m.Code == "PVC").Id;
        var name = Unique("عميل تصدير");
        var customer = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), name, true, false, [new PhoneInput(Mobile())],
            Interests: [new InterestInput(materialId, GradeId: gradeId), .. ApiFactory.FixtureInterests])));
        var supplier = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), Unique("مورد تصدير"), false, true, [new PhoneInput(Mobile())],
            Products: [new ProductInput(materialId, GradeId: gradeId)])));

        var byGrade = await Read<ExportResult>(await Post(admin, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Mixed, materialId, gradeId)));
        Assert.Contains(byGrade.Rows, r => r.PartyId == customer.Id && r.Kind == "customer");
        Assert.Contains(byGrade.Rows, r => r.PartyId == supplier.Id && r.Kind == "supplier");
        // الارتباطات غير المطابقة لا تظهر.
        Assert.All(byGrade.Rows, r => Assert.Equal(grade, r.Grade!.ToLowerInvariant()));
        Assert.Single(byGrade.Rows, r => r.PartyId == customer.Id);
        Assert.StartsWith("010", byGrade.Rows.First(r => r.PartyId == customer.Id).Phone);

        var all = await Read<ExportResult>(await Post(admin, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Customers)));
        Assert.True(all.Rows.Count(r => r.PartyId == customer.Id) >= 2); // كل ارتباطاته
        Assert.DoesNotContain(all.Rows, r => r.Kind == "supplier");
        Assert.Equal("validation", await Code(await Post(admin, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Customers, otherMaterial, gradeId))));

        var xlsx = await admin.PostAsJsonAsync("/api/v1/quick-entry/export/excel",
            new ExportRequest(QuickEntryAudience.Mixed, materialId), Json);
        var sheets = XlsxReader.ReadSheets(await xlsx.Content.ReadAsStreamAsync());
        Assert.Equal(["العملاء", "الموردون"], sheets.Select(s => s.Name));
        Assert.Contains(sheets[0].Rows, r => r[0] == name && r[1].StartsWith('0'));

        var sales = await ClientAs(SystemRoles.SalesManager);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(sales, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Suppliers))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(sales, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Mixed))).StatusCode);
        var rep = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(rep, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Customers))).StatusCode);
    }

    [Fact]
    public async Task Undo_reverses_only_untouched_records_of_the_batch()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var (_, grade, _, _) = await GradeAsync(admin);
        var keep = Row(1, Unique("عميل يُعدل"), Mobile(), "PP", grade);
        var undo = Row(2, Unique("عميل يُلغى"), Mobile(), "PP", grade);
        var pending = Row(3, Unique("ناقص"), null, "PP", grade);
        var request = new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Customers,
            [keep, undo, pending]);
        await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", request));
        Assert.Equal(HttpStatusCode.OK, (await Post(admin, $"/api/v1/parties/{keep.Id}/contacts",
            new ContactInput(Guid.CreateVersion7(), "موظف", null, Mobile()))).StatusCode);

        var rep = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(rep, $"/api/v1/quick-entry/batches/{request.Id}/undo", new { })).StatusCode);

        var result = await Read<UndoResult>(await Post(admin, $"/api/v1/quick-entry/batches/{request.Id}/undo", new { }));
        Assert.Equal(1, result.Reversed);
        Assert.Equal(1, result.Discarded);
        Assert.Equal(keep.Id, result.Blocked.Single().PartyId);
        Assert.Equal("partially_undone", result.Status);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/v1/parties/{undo.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/v1/parties/{keep.Id}")).StatusCode);
        var batches = await Read<List<QuickBatchSummary>>(await admin.GetAsync("/api/v1/quick-entry/batches"));
        Assert.Contains(batches, b => b.Id == request.Id && b.Status == "partially_undone");
    }
}
