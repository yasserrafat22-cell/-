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

/// <summary>مطابقة الموردين، المتابعات المستحقة، والتقارير — كلها داخل حدود الصلاحيات.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class InsightsApiTests(ApiFactory api)
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

    private static async Task<PartyDetail> Create(HttpClient client, CreatePartyRequest request)
    {
        var response = await Post(client, "/api/v1/parties", request with { ConfirmSimilar = true });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await Read<PartyDetail>(response);
    }

    private static async Task<CatalogGradeDto> Grade(HttpClient client, Guid material, Guid maker, string code) =>
        await Read<CatalogGradeDto>(await Post(client, "/api/v1/catalog/grades", new CreateGradeRequest(material, maker, code)));

    [Fact]
    public async Task Supplier_matching_ranks_exact_matches_and_explains_alternatives()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        var sa = refs.Countries.First(c => c.Code == "SA").Id;
        var ton = refs.Units.First(u => u.Code == "ton").Id;
        var makerA = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"صانع {Guid.NewGuid():N}"[..16])));
        var makerB = await Read<ManufacturerDto>(await Post(admin, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest($"صانع {Guid.NewGuid():N}"[..16])));
        var wanted = await Grade(admin, pp, makerA.Id, $"W{Guid.NewGuid():N}"[..8]);
        var sibling = await Grade(admin, pp, makerA.Id, $"S{Guid.NewGuid():N}"[..8]);
        var other = await Grade(admin, pp, makerB.Id, $"O{Guid.NewGuid():N}"[..8]);

        CreatePartyRequest Supplier(string name, Guid grade, Guid? origin) => new(Guid.CreateVersion7(), name, false, true,
            [new PhoneInput(UniquePhone())], SupplierActivityId: refs.ActivityTypes.First(a => a.Code == "importer").Id,
            Products: [new ProductInput(pp, GradeId: grade, OriginCountryId: origin)]);
        var exact = await Create(admin, Supplier("مورد مطابق تمامًا", wanted.Id, sa));
        var wrongOrigin = await Create(admin, Supplier("مورد بلد آخر", wanted.Id, refs.Countries.First(c => c.Code != "SA").Id));
        var sameMaker = await Create(admin, Supplier("مورد نفس الشركة", sibling.Id, null));
        await Create(admin, Supplier("مورد شركة أخرى", other.Id, null));
        await Post(admin, $"/api/v1/supplier-products/{exact.Products[0].Id}/quotes", new CreateQuoteRequest(
            Guid.CreateVersion7(), 45000, "EGP", ton, DateOnly.FromDateTime(DateTime.UtcNow)));

        var customer = await Create(admin, new CreatePartyRequest(Guid.CreateVersion7(), "عميل يحتاج PP", true, false,
            [new PhoneInput(UniquePhone())], CustomerActivityId: refs.ActivityTypes.First(a => a.Code == "factory").Id,
            Interests: [new InterestInput(pp, GradeId: wanted.Id, OriginCountryId: sa)]));

        var matches = await Read<SupplierMatches>(await admin.GetAsync($"/api/v1/parties/{customer.Id}/supplier-matches"));
        var first = matches.Exact[0];
        Assert.Equal(exact.Id, first.SupplierId);
        Assert.Contains("نفس الخامة والشركة المصنّعة والـ Grade", first.Reasons);
        Assert.Contains("نفس بلد الصنع المطلوب", first.Reasons);
        Assert.Equal(45000m, first.LatestPrice!.Price);
        Assert.DoesNotContain(matches.Exact, m => m.SupplierId == wrongOrigin.Id);

        var alt = matches.Alternatives;
        Assert.Contains(alt, m => m.SupplierId == wrongOrigin.Id && m.Reasons.Contains("نفس الـ Grade لكن بلد الصنع مختلف عن المطلوب"));
        Assert.Contains(alt, m => m.SupplierId == sameMaker.Id && m.Reasons.Contains("نفس الشركة المصنّعة بـ Grade مختلف"));
        // ترتيب واضح: بلد مختلف (60) قبل نفس الشركة (50) قبل شركة أخرى (30).
        Assert.True(alt.Select(m => m.Score).SequenceEqual(alt.Select(m => m.Score).OrderByDescending(s => s)));
        // لا سعر مُخترع لمن لا عرض سعر له.
        Assert.All(alt, m => Assert.Null(m.LatestPrice));

        // المندوب لا يصل لنتائج تكشف الموردين حتى لعميله.
        var rep = await ClientAs(SystemRoles.Representative);
        var own = await Create(rep, new CreatePartyRequest(Guid.CreateVersion7(), "عميل المندوب", true, false,
            [new PhoneInput(UniquePhone())], Interests: [new InterestInput(pp, GradeId: wanted.Id)]));
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.GetAsync($"/api/v1/parties/{own.Id}/supplier-matches")).StatusCode);
        var secretary = await ClientAs(SystemRoles.Secretary);
        Assert.Equal(HttpStatusCode.OK, (await secretary.GetAsync($"/api/v1/parties/{own.Id}/supplier-matches")).StatusCode);
    }

    [Fact]
    public async Task Follow_ups_are_listed_by_status_and_only_own_ones_notify()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var secretary = await ClientAs(SystemRoles.Secretary);
        var refs = (await rep.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var reached = refs.ContactOutcomes.First(o => o.Code == "reached").Id;
        var party = await Create(rep, new CreatePartyRequest(Guid.CreateVersion7(), "عميل متابعات", true, false,
            [new PhoneInput(UniquePhone())]));
        var later = DateTimeOffset.UtcNow.AddDays(3);
        Assert.Equal(HttpStatusCode.OK, (await Post(rep, $"/api/v1/parties/{party.Id}/interactions",
            new CreateInteractionRequest(Guid.CreateVersion7(), ContactChannel.Call, reached, NextFollowUpAt: later,
                Remind: true))).StatusCode);

        var mine = await Read<List<FollowUpItem>>(await rep.GetAsync("/api/v1/follow-ups?days=7"));
        var item = mine.Single(f => f.PartyId == party.Id);
        Assert.Equal("upcoming", item.Status);
        Assert.True(item.Mine);
        Assert.True(item.Remind);

        var office = await Read<List<FollowUpItem>>(await secretary.GetAsync("/api/v1/follow-ups?days=7"));
        Assert.False(office.Single(f => f.PartyId == party.Id).Mine);

        // مندوب آخر لا يرى متابعات عميل ليس له.
        var other = await ClientAs(SystemRoles.Representative);
        Assert.DoesNotContain(await Read<List<FollowUpItem>>(await other.GetAsync("/api/v1/follow-ups?days=7")),
            f => f.PartyId == party.Id);

        // تسجيل تواصل جديد يغلق المتابعة السابقة فتختفي من القائمة (ويُلغى إشعارها في التطبيق).
        await Post(rep, $"/api/v1/parties/{party.Id}/interactions",
            new CreateInteractionRequest(Guid.CreateVersion7(), ContactChannel.WhatsApp, reached));
        Assert.DoesNotContain(await Read<List<FollowUpItem>>(await rep.GetAsync("/api/v1/follow-ups?days=7")),
            f => f.PartyId == party.Id);
    }

    [Fact]
    public async Task Reports_stay_within_the_viewer_scope()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = (await rep.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var marker = $"تقرير{Random.Shared.Next(100000, 999999)}";
        await Create(rep, new CreatePartyRequest(Guid.CreateVersion7(), $"شركة {marker}", true, false,
            [new PhoneInput(UniquePhone())], Interests: [new InterestInput(refs.Materials.First(m => m.Code == "PVC").Id)]));
        await Create(admin, new CreatePartyRequest(Guid.CreateVersion7(), $"مصنع {marker}", true, false,
            [new PhoneInput(UniquePhone())]));

        var repReport = await Read<ReportSummary>(await rep.GetAsync("/api/v1/reports/summary"));
        Assert.Single(repReport.Representatives);
        Assert.Equal(1, repReport.Representatives[0].NewCustomers);
        Assert.Contains(repReport.Materials, m => m.Spec.StartsWith("PVC", StringComparison.Ordinal) && m.Suppliers is null);
        Assert.Null(repReport.Quality);

        var adminReport = await Read<ReportSummary>(await admin.GetAsync("/api/v1/reports/summary"));
        Assert.NotNull(adminReport.Quality);
        Assert.Contains(adminReport.Quality!.PossibleDuplicates, d => d.Names.Count >= 2 && d.Names.All(n => n.Contains(marker)));
        Assert.All(adminReport.Materials, m => Assert.NotNull(m.Suppliers));
    }
}
