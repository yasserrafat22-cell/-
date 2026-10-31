using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>كتالوج الشركات المصنّعة والـ Grades، والمواصفات الدقيقة والمفتوحة.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class CatalogApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string Unique(string prefix) => $"{prefix}_{Guid.NewGuid():N}"[..20];

    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private async Task<HttpClient> ClientAs(string role)
    {
        var username = Unique(role[..3]);
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

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<ReferenceBundle> Reference(HttpClient client) =>
        await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));

    private static async Task<ManufacturerDto> Maker(HttpClient client, string name) =>
        await Read<ManufacturerDto>(await Post(client, "/api/v1/catalog/manufacturers", new CreateManufacturerRequest(name)));

    private static Guid Material(ReferenceBundle refs, string code) => refs.Materials.First(m => m.Code == code).Id;

    [Fact]
    public async Task Representative_adds_grade_that_is_visible_immediately()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(rep);
        var makerName = Unique("مصنع");

        var created = await Post(rep, "/api/v1/catalog/manufacturers", new CreateManufacturerRequest(makerName));
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var maker = await Read<ManufacturerDto>(created);
        var again = await Post(rep, "/api/v1/catalog/manufacturers", new CreateManufacturerRequest(" " + makerName.ToUpperInvariant()));
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
        Assert.Equal(maker.Id, (await Read<ManufacturerDto>(again)).Id);

        var sa = refs.Countries.First(c => c.Code == "SA").Id;
        var code = Unique("PP");
        var grade = await Read<CatalogGradeDto>(await Post(rep, "/api/v1/catalog/grades",
            new CreateGradeRequest(Material(refs, "PP"), maker.Id, code, [sa])));
        // الكتالوج موحد: الـ Grade الجديد يظهر للجميع فورًا دون انتظار اعتماد.
        Assert.True(grade.IsVerified);
        Assert.Equal([sa], grade.OriginIds);

        // نفس الـ Grade لنفس الشركة يعيد الموجود ولا ينشئ نسخة ثانية.
        var same = await Post(rep, "/api/v1/catalog/grades",
            new CreateGradeRequest(Material(refs, "PP"), maker.Id, code.ToLowerInvariant()));
        Assert.Equal(HttpStatusCode.OK, same.StatusCode);
        Assert.Equal(grade.Id, (await Read<CatalogGradeDto>(same)).Id);

        Assert.Equal(HttpStatusCode.Forbidden, (await rep.PostAsync($"/api/v1/catalog/grades/{grade.Id}/verify", null)).StatusCode);
        var pending = await Read<List<CatalogGradeDto>>(await admin.GetAsync("/api/v1/catalog/grades?pending=true"));
        Assert.DoesNotContain(pending, g => g.Id == grade.Id);

        var bundle = await Reference(rep);
        Assert.Contains(bundle.Materials.SelectMany(m => m.Grades),
            g => g.Id == grade.Id && g.ManufacturerId == maker.Id && g.IsVerified);
        Assert.Contains(bundle.Manufacturers, m => m.Id == maker.Id);
    }

    [Fact]
    public async Task Same_code_for_another_manufacturer_needs_confirmation()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(rep);
        var first = await Maker(rep, Unique("أ"));
        var second = await Maker(rep, Unique("ب"));
        var code = Unique("G");
        await Post(rep, "/api/v1/catalog/grades", new CreateGradeRequest(Material(refs, "HDPE"), first.Id, code));

        var similar = await Post(rep, "/api/v1/catalog/grades", new CreateGradeRequest(Material(refs, "HDPE"), second.Id, code));
        Assert.Equal(HttpStatusCode.Conflict, similar.StatusCode);
        Assert.Equal("catalog.similar_grade", await Code(similar));

        var confirmed = await Post(rep, "/api/v1/catalog/grades",
            new CreateGradeRequest(Material(refs, "HDPE"), second.Id, code, ConfirmSimilar: true));
        Assert.Equal(HttpStatusCode.Created, confirmed.StatusCode);
    }

    [Fact]
    public async Task Open_exact_and_unknown_manufacturer_specs_are_kept_apart()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(rep);
        var maker = await Maker(rep, Unique("مصنع"));
        var pp = Material(refs, "PP");
        var grade = await Read<CatalogGradeDto>(await Post(rep, "/api/v1/catalog/grades",
            new CreateGradeRequest(pp, maker.Id, Unique("PP"))));
        var sa = refs.Countries.First(c => c.Code == "SA").Id;

        var request = new CreatePartyRequest(Guid.CreateVersion7(), "عميل مواصفات", true, false,
            [new PhoneInput(UniquePhone())],
            Interests:
            [
                new InterestInput(pp, GradeId: grade.Id, OriginCountryId: sa),
                new InterestInput(Material(refs, "HDPE"), OpenSpec: true),
                new InterestInput(Material(refs, "PVC"), GradeCode: Unique("OLD")),
                new InterestInput(Material(refs, "LDPE")),
            ], ConfirmSimilar: true);
        var party = await Read<PartyDetail>(await Post(rep, "/api/v1/parties", request));
        var specs = party.Interests.Select(i => i.Spec!).ToList();

        var exact = specs.Single(s => s.MaterialCode == "PP");
        Assert.Equal(SpecPrecision.Exact, exact.Precision);
        Assert.Equal(maker.Name, exact.ManufacturerName);
        Assert.Equal("السعودية", exact.OriginName);
        Assert.True(exact.GradeVerified);
        Assert.Equal(SpecPrecision.Open, specs.Single(s => s.MaterialCode == "HDPE").Precision);
        Assert.Equal(SpecPrecision.UnknownManufacturer, specs.Single(s => s.MaterialCode == "PVC").Precision);
        Assert.Equal(SpecPrecision.Unspecified, specs.Single(s => s.MaterialCode == "LDPE").Precision);
    }

    [Fact]
    public async Task A_grade_may_be_added_without_guessing_its_manufacturer()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(rep);
        var request = new CreateGradeRequest(Material(refs, "PP"), null, Unique("668"), Id: Guid.CreateVersion7());
        var created = await Post(rep, "/api/v1/catalog/grades", request);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var grade = await Read<CatalogGradeDto>(created);
        Assert.Null(grade.ManufacturerId);
        // إعادة الإرسال (مثلًا من طابور المزامنة) تعيد نفس الـ Grade.
        var again = await Post(rep, "/api/v1/catalog/grades", request);
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
        Assert.Equal(grade.Id, (await Read<CatalogGradeDto>(again)).Id);
    }

    [Fact]
    public async Task Invalid_specs_are_rejected_by_the_server()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var maker = await Maker(admin, Unique("مصنع"));
        var ppGrade = await Read<CatalogGradeDto>(await Post(admin, "/api/v1/catalog/grades",
            new CreateGradeRequest(Material(refs, "PP"), maker.Id, Unique("PP"))));

        async Task<string?> Customer(InterestInput interest) => await Code(await Post(admin, "/api/v1/parties",
            new CreatePartyRequest(Guid.CreateVersion7(), "عميل", true, false, [new PhoneInput(UniquePhone())],
                Interests: [interest, .. ApiFactory.FixtureInterests], ConfirmSimilar: true)));

        Assert.Equal("spec.open_with_grade", await Customer(new InterestInput(Material(refs, "PP"), GradeId: ppGrade.Id, OpenSpec: true)));
        Assert.Equal("spec.grade_material_mismatch", await Customer(new InterestInput(Material(refs, "HDPE"), GradeId: ppGrade.Id)));
        Assert.Equal("spec.unknown_country", await Customer(new InterestInput(Material(refs, "PP"),
            OriginCountryId: refs.Governorates[0].Id)));

        var supplier = await Post(admin, "/api/v1/parties", new CreatePartyRequest(Guid.CreateVersion7(), "مورد", false, true,
            [new PhoneInput(UniquePhone())], Products: [new ProductInput(Material(refs, "PP"))], ConfirmSimilar: true));
        var supplierId = (await Read<PartyDetail>(supplier)).Id;
        var supply = await Post(admin, "/api/v1/supplies", new CreateSupplyRequest(Guid.CreateVersion7(), supplierId,
            new DateOnly(2026, 10, 20), [new LineInput(Material(refs, "PP"), 1, refs.Units[0].Id, OpenSpec: true)]));
        Assert.Equal("spec.open_not_allowed", await Code(supply));
    }

    [Fact]
    public async Task Admin_links_a_legacy_grade_to_its_manufacturer_and_records_follow()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var pvc = Material(refs, "PVC");
        var legacyCode = Unique("SG");
        var party = await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), "عميل قديم", true, false, [new PhoneInput(UniquePhone())],
            Interests: [new InterestInput(pvc, GradeCode: legacyCode)], ConfirmSimilar: true)));
        var legacy = party.Interests.Single().GradeId!.Value;

        var order = await Post(admin, "/api/v1/orders", new CreateOrderRequest(Guid.CreateVersion7(), party.Id,
            new DateOnly(2026, 10, 20), [new LineInput(pvc, 2, refs.Units.First(u => u.Code == "ton").Id, GradeId: legacy)],
            OrderStage.Confirmed));
        Assert.Equal(HttpStatusCode.OK, order.StatusCode);

        var maker = await Maker(admin, Unique("مصنع"));
        var updated = await admin.PutAsJsonAsync($"/api/v1/catalog/grades/{legacy}",
            new UpdateGradeRequest(maker.Id, legacyCode), Json);
        Assert.Equal(HttpStatusCode.OK, updated.StatusCode);

        var reloaded = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{party.Id}"));
        Assert.Equal(SpecPrecision.Exact, reloaded.Interests.Single().Spec!.Precision);
        var orders = await Read<List<OrderDto>>(await admin.GetAsync($"/api/v1/parties/{party.Id}/orders"));
        Assert.Equal(maker.Name, orders.Single().Lines.Single().Spec!.ManufacturerName);

        // لا يمكن إلغاء الشركة بعد ربطها.
        var unlink = await admin.PutAsJsonAsync($"/api/v1/catalog/grades/{legacy}",
            new UpdateGradeRequest(null, legacyCode), Json);
        Assert.Equal(HttpStatusCode.BadRequest, unlink.StatusCode);
    }
}
