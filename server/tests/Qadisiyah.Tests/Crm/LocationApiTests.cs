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

/// <summary>مواقع العملاء والموردين واختيارها في الطلبات والتوريدات.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class LocationApiTests(ApiFactory api)
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
        var session = await api.LoginAsync(username, Password);
        return api.CreateClient(session.AccessToken);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Json))!;

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<string?> Code(HttpResponseMessage response)
    {
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.TryGetProperty("code", out var c) ? c.GetString() : null;
    }

    private static async Task<PartyDetail> Party(HttpClient client, bool customer = true) =>
        await Read<PartyDetail>(await Post(client, "/api/v1/parties", new CreatePartyRequest(
            Guid.CreateVersion7(), customer ? "عميل مواقع" : "مورد مواقع", customer, !customer,
            [new PhoneInput(UniquePhone())], ConfirmSimilar: true)));

    private static LocationInput Location(LocationKind kind, string? url = null, double? lat = null, double? lng = null,
        bool isDefault = false) => new(Guid.CreateVersion7(), kind, AddressLine: "المنطقة الصناعية - عنوان تجريبي",
        MapsUrl: url, Latitude: lat, Longitude: lng, AccessNotes: "البوابة 2", IsDefault: isDefault);

    [Fact]
    public async Task First_location_is_default_and_only_one_default_is_kept()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var party = await Party(client);

        var first = await Read<LocationDto>(await Post(client, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Factory, "https://maps.google.com/?q=30.2950,31.7420", 30.295, 31.742)));
        Assert.True(first.IsDefault);
        // رابط مختصر بلا إحداثيات يُحفظ كما هو.
        var second = await Read<LocationDto>(await Post(client, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Warehouse, "https://maps.app.goo.gl/AbCdEf123", isDefault: true)));
        Assert.True(second.IsDefault);
        Assert.Null(second.Latitude);
        Assert.Equal("https://maps.app.goo.gl/AbCdEf123", second.MapsUrl);

        var list = await Read<List<LocationDto>>(await client.GetAsync($"/api/v1/parties/{party.Id}/locations"));
        Assert.Equal([second.Id], list.Where(l => l.IsDefault).Select(l => l.Id));

        // إعادة الإرسال بنفس المعرف لا تكرر الموقع.
        var again = await Post(client, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Warehouse) with { Id = second.Id });
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
        Assert.Equal(2, (await Read<List<LocationDto>>(await client.GetAsync($"/api/v1/parties/{party.Id}/locations"))).Count);
    }

    [Fact]
    public async Task Invalid_links_and_coordinates_are_rejected()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var party = await Party(client);
        Assert.Equal("location.invalid_url", await Code(await Post(client, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Factory, "https://evil.example.com/maps"))));
        Assert.Equal("location.invalid_coordinates", await Code(await Post(client, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Factory, lat: 95, lng: 31))));
        Assert.Equal("location.invalid_coordinates", await Code(await Post(client, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Factory, lat: 30))));
    }

    [Fact]
    public async Task Each_order_can_use_another_location_without_changing_the_default()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));
        var customer = await Party(client);
        var main = await Read<LocationDto>(await Post(client, $"/api/v1/parties/{customer.Id}/locations",
            Location(LocationKind.Factory)));
        var other = await Read<LocationDto>(await Post(client, $"/api/v1/parties/{customer.Id}/locations",
            Location(LocationKind.Delivery)));

        var order = await Post(client, "/api/v1/orders", new CreateOrderRequest(Guid.CreateVersion7(), customer.Id,
            new DateOnly(2026, 10, 28), [new LineInput(refs.Materials[0].Id, 1, refs.Units[0].Id)],
            DeliveryLocationId: other.Id));
        Assert.Equal(other.Id, (await Read<OrderDto>(order)).DeliveryLocationId);
        var list = await Read<List<LocationDto>>(await client.GetAsync($"/api/v1/parties/{customer.Id}/locations"));
        Assert.Equal(main.Id, list.Single(l => l.IsDefault).Id);

        // موقع طرف آخر مرفوض.
        var stranger = await Party(client);
        var foreign = await Read<LocationDto>(await Post(client, $"/api/v1/parties/{stranger.Id}/locations",
            Location(LocationKind.Factory)));
        var rejected = await Post(client, "/api/v1/orders", new CreateOrderRequest(Guid.CreateVersion7(), customer.Id,
            new DateOnly(2026, 10, 28), [new LineInput(refs.Materials[0].Id, 1, refs.Units[0].Id)],
            DeliveryLocationId: foreign.Id));
        Assert.Equal("location.not_owned", await Code(rejected));
    }

    [Fact]
    public async Task Removing_a_location_keeps_orders_that_used_it()
    {
        var client = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));
        var supplier = await Party(client, customer: false);
        var place = await Read<LocationDto>(await Post(client, $"/api/v1/parties/{supplier.Id}/locations",
            Location(LocationKind.Loading)));
        var supply = await Read<SupplyDto>(await Post(client, "/api/v1/supplies", new CreateSupplyRequest(
            Guid.CreateVersion7(), supplier.Id, new DateOnly(2026, 10, 28),
            [new LineInput(refs.Materials[0].Id, 2, refs.Units[0].Id)], LoadingLocationId: place.Id)));

        Assert.Equal(HttpStatusCode.OK, (await client.DeleteAsync($"/api/v1/locations/{place.Id}")).StatusCode);
        Assert.Empty(await Read<List<LocationDto>>(await client.GetAsync($"/api/v1/parties/{supplier.Id}/locations")));
        var supplies = await Read<List<SupplyDto>>(await client.GetAsync($"/api/v1/parties/{supplier.Id}/supplies"));
        Assert.Equal(place.Id, supplies.Single(s => s.Id == supply.Id).LoadingLocationId);

        var history = await Read<List<HistoryItem>>(await client.GetAsync($"/api/v1/parties/{supplier.Id}/history"));
        Assert.Contains(history, h => h.Description.StartsWith("حذف الموقع", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Read_only_users_cannot_change_locations()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var party = await Party(admin);
        var place = await Read<LocationDto>(await Post(admin, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Factory)));
        // السكرتارية ترى وتضيف ولا تعدّل المحفوظ؛ المندوب لا يرى عميلًا ليس له.
        var secretary = await ClientAs(SystemRoles.Secretary);
        Assert.Equal(HttpStatusCode.OK, (await secretary.GetAsync($"/api/v1/parties/{party.Id}/locations")).StatusCode);
        var update = await secretary.PutAsJsonAsync($"/api/v1/locations/{place.Id}",
            Location(LocationKind.Warehouse) with { Id = place.Id, Version = place.Version }, Json);
        Assert.Equal(HttpStatusCode.Forbidden, update.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await secretary.DeleteAsync($"/api/v1/locations/{place.Id}")).StatusCode);
        var added = await Read<LocationDto>(await Post(secretary, $"/api/v1/parties/{party.Id}/locations",
            Location(LocationKind.Warehouse) with { IsDefault = true }));
        Assert.False(added.IsDefault);

        var rep = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/parties/{party.Id}/locations")).StatusCode);
    }
}
