using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>البحث اللحظي الموحد: الموردون أولًا ثم العملاء، بالأسباب وضمن الصلاحيات، والمشاركة الجماعية.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class SearchApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

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

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<PartyDetail> Create(HttpClient client, CreatePartyRequest request) =>
        await Read<PartyDetail>(await Post(client, "/api/v1/parties", request with { ConfirmSimilar = true }));

    private sealed record World(Guid Pp, Guid Grade, Guid Maker, string MakerName, PartyDetail Supplier,
        PartyDetail Customer, PartyDetail OpenCustomer, string SupplierPhone, string Marker);

    private static async Task<World> SetUp(HttpClient admin)
    {
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var marker = Random.Shared.Next(100000, 999999).ToString(System.Globalization.CultureInfo.InvariantCulture);
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        var makerName = $"سابك {marker}";
        var maker = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest(makerName)));
        var grade = await Read<CatalogGradeDto>(await Post(admin, "/api/v1/catalog/grades",
            new CreateGradeRequest(pp, maker.Id, $"5{marker}P")));
        var phone = UniquePhone();
        var supplier = await Create(admin, new CreatePartyRequest(Guid.CreateVersion7(), $"مورد النور {marker}", false, true,
            [new PhoneInput(phone)], Products: [new ProductInput(pp, GradeId: grade.Id)]));
        var customer = await Create(admin, new CreatePartyRequest(Guid.CreateVersion7(), $"عميل الأمل {marker}", true, false,
            [new PhoneInput(UniquePhone())], Interests: [new InterestInput(pp, GradeId: grade.Id)]));
        var open = await Create(admin, new CreatePartyRequest(Guid.CreateVersion7(), $"عميل مفتوح {marker}", true, false,
            [new PhoneInput(UniquePhone())], Interests: ApiFactory.WithGrade([new InterestInput(pp, OpenSpec: true)])));
        await Post(admin, $"/api/v1/parties/{customer.Id}/contacts",
            new ContactInput(Guid.CreateVersion7(), $"موظف {marker}", "مشتريات", "01112345678"));
        return new World(pp, grade.Id, maker.Id, makerName, supplier, customer, open, phone, marker);
    }

    private static Task<SearchResult> Search(HttpClient client, string query) =>
        client.GetFromJsonAsync<SearchResult>("/api/v1/search?" + query, Json)!;

    [Fact]
    public async Task Grade_search_lists_suppliers_first_then_matching_customers_with_reasons()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var w = await SetUp(admin);
        var result = await Search(admin, $"gradeId={w.Grade}");
        Assert.Contains(result.Suppliers, c => c.PartyId == w.Supplier.Id && c.Exact);
        var exact = result.Customers.Single(c => c.PartyId == w.Customer.Id);
        Assert.True(exact.Exact);
        Assert.Contains(exact.Reasons, r => r.StartsWith("يحتاج", StringComparison.Ordinal));
        // جهة الاتصال الأساسية تظهر في البطاقة.
        Assert.Equal("+201112345678", exact.Phone);
        var open = result.Customers.Single(c => c.PartyId == w.OpenCustomer.Id);
        Assert.False(open.Exact);
        Assert.Contains(open.Reasons, r => r.Contains("يقبل أي شركة", StringComparison.Ordinal));
        Assert.True(result.Customers.ToList().IndexOf(exact) < result.Customers.ToList().IndexOf(open));
    }

    [Fact]
    public async Task Manufacturer_name_in_arabic_suggests_its_grades_and_partial_grade_works()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var w = await SetUp(admin);
        var byMaker = await Search(admin, "q=" + Uri.EscapeDataString(w.MakerName));
        Assert.Contains(byMaker.Suggestions, s => s.Kind == "manufacturer" && s.Id == w.Maker);
        Assert.Contains(byMaker.Suggestions, s => s.Kind == "grade" && s.Id == w.Grade);
        Assert.Contains(byMaker.Suggestions, s => s.Kind == "material" && s.Id == w.Pp);
        Assert.Contains(byMaker.Suppliers, c => c.PartyId == w.Supplier.Id);

        var partial = await Search(admin, "q=" + w.Marker[..4]);
        Assert.Contains(partial.Suggestions, s => s.Kind == "grade" && s.Id == w.Grade);
    }

    [Fact]
    public async Task Supplier_or_customer_name_search_crosses_to_the_other_side()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var w = await SetUp(admin);
        var bySupplier = await Search(admin, "q=" + Uri.EscapeDataString($"مورد النور {w.Marker}"));
        Assert.Equal(w.Supplier.Id, bySupplier.Suppliers[0].PartyId);
        Assert.Contains(bySupplier.Customers, c => c.PartyId == w.Customer.Id && c.Exact);

        var byCustomer = await Search(admin, "q=" + Uri.EscapeDataString($"عميل الأمل {w.Marker}"));
        Assert.Contains(byCustomer.Customers, c => c.PartyId == w.Customer.Id);
        Assert.Contains(byCustomer.Suppliers, c => c.PartyId == w.Supplier.Id && c.Exact);

        var byPhone = await Search(admin, "q=" + w.SupplierPhone[^7..]);
        Assert.Contains(byPhone.Suppliers, c => c.PartyId == w.Supplier.Id);
        var byEmployee = await Search(admin, "q=" + Uri.EscapeDataString($"موظف {w.Marker}"));
        Assert.Contains(byEmployee.Customers, c => c.PartyId == w.Customer.Id);
    }

    [Fact]
    public async Task Sales_manager_and_reps_never_get_supplier_cards()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var w = await SetUp(admin);
        foreach (var role in new[] { SystemRoles.SalesManager, SystemRoles.Representative })
        {
            var client = await ClientAs(role);
            var bySupplierName = await Search(client, "q=" + Uri.EscapeDataString($"مورد النور {w.Marker}"));
            Assert.Empty(bySupplierName.Suppliers);
            var byPhone = await Search(client, "q=" + w.SupplierPhone[^7..]);
            Assert.Empty(byPhone.Suppliers);
            var byGrade = await Search(client, $"gradeId={w.Grade}");
            Assert.Empty(byGrade.Suppliers);
            Assert.DoesNotContain(w.SupplierPhone[^7..], JsonSerializer.Serialize(byGrade));
        }
        // المندوب لا يرى عملاء غيره في البحث.
        var rep = await ClientAs(SystemRoles.Representative);
        Assert.Empty((await Search(rep, $"gradeId={w.Grade}")).Customers);
    }

    [Fact]
    public async Task Bulk_share_and_export_are_blocked_for_reps_and_audited()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var w = await SetUp(admin);
        var rep = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.OK, (await Post(rep, "/api/v1/share/authorize", new ShareRequest("card", 1))).StatusCode);
        foreach (var bulk in new[] { new ShareRequest("selection", 2), new ShareRequest("pdf", 1), new ShareRequest("print", 3) })
            Assert.Equal(HttpStatusCode.Forbidden, (await Post(rep, "/api/v1/share/authorize", bulk)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await Post(rep, "/api/v1/export/search", new SearchExportRequest(null, GradeId: w.Grade))).StatusCode);

        var secretary = await ClientAs(SystemRoles.Secretary);
        Assert.Equal(HttpStatusCode.OK,
            (await Post(secretary, "/api/v1/share/authorize", new ShareRequest("list", 20, "PP"))).StatusCode);
        var excel = await Post(secretary, "/api/v1/export/search",
            new SearchExportRequest(null, GradeId: w.Grade, PartyIds: [w.Supplier.Id, w.Customer.Id]));
        Assert.Equal(HttpStatusCode.OK, excel.StatusCode);
        using var zip = new ZipArchive(new MemoryStream(await excel.Content.ReadAsByteArrayAsync()));
        var sheet = await new StreamReader(zip.GetEntry("xl/worksheets/sheet1.xml")!.Open(), Encoding.UTF8).ReadToEndAsync();
        Assert.True(sheet.IndexOf("مورد النور", StringComparison.Ordinal) < sheet.IndexOf("عميل الأمل", StringComparison.Ordinal));
        Assert.DoesNotContain("عميل مفتوح", sheet);

        var audit = await Read<PagedResult<AuditItem>>(await admin.GetAsync("/api/v1/audit?action=share."));
        Assert.Contains(audit.Items, a => a.Action == "share.list");
    }
}
