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

/// <summary>«السجل»: البحث والفلاتر الدقيقة والمفتوحة، والمفضلة، وسجل التعديلات.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class RegistryApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string Unique(string prefix) => $"{prefix}{Guid.NewGuid():N}"[..14];

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

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<PagedResult<RegistryItem>> List(HttpClient client, string query) =>
        await Read<PagedResult<RegistryItem>>(await client.GetAsync("/api/v1/parties?" + query));

    private static async Task<PartyDetail> Customer(HttpClient client, string name, params InterestInput[] interests) =>
        await Read<PartyDetail>(await Post(client, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), name, true, false, [new PhoneInput(UniquePhone())], Interests: interests)));

    [Fact]
    public async Task Search_finds_by_name_phone_and_material_text()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));
        var tag = Unique("سجل");
        var maker = await Read<ManufacturerDto>(await Post(client, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest(Unique("مصنع"))));
        var gradeCode = Unique("GX");
        var grade = await Read<CatalogGradeDto>(await Post(client, "/api/v1/catalog/grades",
            new CreateGradeRequest(refs.Materials.First(m => m.Code == "PP").Id, maker.Id, gradeCode)));
        var party = await Customer(client, $"عميل {tag}",
            new InterestInput(grade.MaterialId, GradeId: grade.Id));

        Assert.Contains((await List(client, $"q={Uri.EscapeDataString(tag)}")).Items, i => i.Id == party.Id);
        var phone = party.Phones[0].E164;
        Assert.Contains((await List(client, $"q=0{phone[3..]}")).Items, i => i.Id == party.Id);
        Assert.Contains((await List(client, $"q={phone[^7..]}")).Items, i => i.Id == party.Id);

        // جزء يبدأ بصفر (كان يُتجاهل قبل الإصلاح): الرقم 01010xxxxxx آخر 7 أرقامه تبدأ بصفر.
        var zeroParty = await Read<PartyDetail>(await Post(client, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), "عميل رقم يبدأ بصفر", true, false,
            [new PhoneInput("01010" + Random.Shared.NextInt64(100_000, 999_999))])));
        var tail = zeroParty.Phones[0].E164[^7..];
        Assert.StartsWith("0", tail, StringComparison.Ordinal);
        Assert.Contains((await List(client, $"q={tail}")).Items, i => i.Id == zeroParty.Id);
        Assert.Contains((await List(client, $"q={gradeCode.ToLowerInvariant()}")).Items, i => i.Id == party.Id);
        Assert.Contains((await List(client, $"q={Uri.EscapeDataString(maker.Name)}")).Items, i => i.Id == party.Id);

        var item = (await List(client, $"q={Uri.EscapeDataString(tag)}")).Items.Single();
        Assert.Equal(gradeCode, item.Specs.Single().GradeCode);
        Assert.Equal(PartyStatus.New, item.Summary!.Status);
        Assert.Null(item.Match);
    }

    [Fact]
    public async Task Spec_filters_separate_exact_and_open_matches()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        var tag = Unique("فلتر");
        var maker = await Read<ManufacturerDto>(await Post(client, "/api/v1/catalog/manufacturers",
            new CreateManufacturerRequest(Unique("مصنع"))));
        var grade = await Read<CatalogGradeDto>(await Post(client, "/api/v1/catalog/grades",
            new CreateGradeRequest(pp, maker.Id, Unique("G"))));

        var exact = await Customer(client, $"دقيق {tag}", new InterestInput(pp, GradeId: grade.Id));
        var open = await Customer(client, $"مفتوح {tag}", new InterestInput(pp, OpenSpec: true));
        var other = await Customer(client, $"آخر {tag}", new InterestInput(refs.Materials.First(m => m.Code == "PVC").Id));

        var byGrade = (await List(client, $"q={Uri.EscapeDataString(tag)}&gradeId={grade.Id}")).Items;
        Assert.Equal(SpecMatch.Exact, byGrade.Single(i => i.Id == exact.Id).Match);
        Assert.Equal(SpecMatch.Open, byGrade.Single(i => i.Id == open.Id).Match);
        Assert.DoesNotContain(byGrade, i => i.Id == other.Id);

        // الشركة وحدها دون خامة: لا تُحسب المواصفات المفتوحة.
        var byMaker = (await List(client, $"q={Uri.EscapeDataString(tag)}&manufacturerId={maker.Id}")).Items;
        Assert.Equal([exact.Id], byMaker.Select(i => i.Id));

        var byMaterial = (await List(client, $"q={Uri.EscapeDataString(tag)}&materialId={pp}&manufacturerId={maker.Id}")).Items;
        Assert.Equal(2, byMaterial.Count);
    }

    [Fact]
    public async Task Favorites_are_per_user_and_idempotent()
    {
        var first = await ClientAs(SystemRoles.SystemAdmin);
        var second = await ClientAs(SystemRoles.SystemAdmin);
        var party = await Customer(first, $"مفضل {Unique("م")}");

        Assert.Equal(HttpStatusCode.OK, (await first.PutAsync($"/api/v1/parties/{party.Id}/favorite", null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await first.PutAsync($"/api/v1/parties/{party.Id}/favorite", null)).StatusCode);
        Assert.Contains((await List(first, "favorites=true")).Items, i => i.Id == party.Id && i.IsFavorite);
        Assert.DoesNotContain((await List(second, "favorites=true")).Items, i => i.Id == party.Id);
        Assert.True((await Read<PartyDetail>(await first.GetAsync($"/api/v1/parties/{party.Id}"))).IsFavorite);

        await first.DeleteAsync($"/api/v1/parties/{party.Id}/favorite");
        Assert.DoesNotContain((await List(first, "favorites=true")).Items, i => i.Id == party.Id);
    }

    [Fact]
    public async Task History_shows_who_changed_what_and_editing_never_duplicates()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var tag = Unique("تعديل");
        var party = await Customer(client, $"قبل {tag}");

        var updated = await client.PutAsJsonAsync($"/api/v1/parties/{party.Id}", new UpdatePartyRequest(
            party.Version, $"بعد {tag}", [new PhoneInput(party.Phones[0].E164)],
            RepresentativeId: party.RepresentativeId), Json);
        Assert.Equal(HttpStatusCode.OK, updated.StatusCode);

        var history = await Read<List<HistoryItem>>(await client.GetAsync($"/api/v1/parties/{party.Id}/history"));
        Assert.Equal("عدّل: الاسم", history[0].Description);
        Assert.Equal("أنشأ السجل", history[^1].Description);
        Assert.All(history, h => Assert.False(string.IsNullOrEmpty(h.UserName)));

        var found = (await List(client, $"q={Uri.EscapeDataString(tag)}")).Items;
        Assert.Equal(party.Id, Assert.Single(found).Id);
        var detail = await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{party.Id}"));
        Assert.True(detail.UpdatedAt > detail.CreatedAt);
    }
}
