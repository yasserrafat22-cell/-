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

/// <summary>
/// قواعد الصلاحيات المعتمدة: المندوب يرى عملاءه فقط ولا يرى أي مورد، ويضيف ولا يعدّل؛
/// السكرتارية ترى الكل وتضيف وتحدد المسؤول والتاريخ؛ التعديل والحذف والاستعادة للمدير العام.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class AccessRulesTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private async Task<(HttpClient Client, Guid UserId)> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        var userId = await api.CreateUserAsync(username, Password, role);
        var session = await api.LoginAsync(username, Password);
        return (api.CreateClient(session.AccessToken), userId);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Json))!;

    private static async Task<JsonElement> Body(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<ReferenceBundle> Reference(HttpClient client) =>
        await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));

    private static CreatePartyRequest Customer(ReferenceBundle refs, string? phone = null) =>
        new(Guid.CreateVersion7(), "عميل صلاحيات", true, false, [new PhoneInput(phone ?? UniquePhone())],
            CustomerActivityId: refs.ActivityTypes.First(a => a.Code == "factory").Id,
            Interests: ApiFactory.FixtureInterests, ConfirmSimilar: true);

    private static CreatePartyRequest Supplier(ReferenceBundle refs, string? phone = null) =>
        new(Guid.CreateVersion7(), "مورد صلاحيات", false, true, [new PhoneInput(phone ?? UniquePhone())],
            SupplierActivityId: refs.ActivityTypes.First(a => a.Code == "importer").Id, ConfirmSimilar: true);

    private static async Task<PartyDetail> Create(HttpClient client, CreatePartyRequest request)
    {
        var response = await Post(client, "/api/v1/parties", request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await Read<PartyDetail>(response);
    }

    private static async Task<List<RegistryItem>> List(HttpClient client, string query = "") =>
        [.. (await Read<PagedResult<RegistryItem>>(await client.GetAsync("/api/v1/parties?take=100&" + query))).Items];

    [Fact]
    public async Task Representative_sees_only_own_customers_and_no_suppliers()
    {
        var (repA, _) = await ClientAs(SystemRoles.Representative);
        var (repB, _) = await ClientAs(SystemRoles.Representative);
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var mine = await Create(repA, Customer(refs));
        var others = await Create(repB, Customer(refs));
        var supplierPhone = UniquePhone();
        var supplier = await Create(admin, Supplier(refs, supplierPhone));

        var listed = await List(repA);
        Assert.Contains(listed, p => p.Id == mine.Id);
        Assert.DoesNotContain(listed, p => p.Id == others.Id || p.Id == supplier.Id || p.IsSupplier);
        Assert.Empty(await List(repA, "role=supplier"));
        // البحث بالرقم لا يكشف المورد.
        Assert.Empty(await List(repA, "q=" + supplierPhone[^6..]));

        Assert.Equal(HttpStatusCode.NotFound, (await repA.GetAsync($"/api/v1/parties/{others.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await repA.GetAsync($"/api/v1/parties/{supplier.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await repA.GetAsync($"/api/v1/parties/{supplier.Id}/supplies")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await repA.GetAsync($"/api/v1/parties/{supplier.Id}/history")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await repA.PutAsync($"/api/v1/parties/{supplier.Id}/favorite", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(repA, "/api/v1/supplies", new CreateSupplyRequest(
            Guid.CreateVersion7(), supplier.Id, new DateOnly(2026, 10, 1),
            [new LineInput(refs.Materials[0].Id, 1, refs.Units[0].Id)]))).StatusCode);
    }

    [Fact]
    public async Task Customer_assigned_to_a_representative_becomes_visible_to_them()
    {
        var (rep, repUserId) = await ClientAs(SystemRoles.Representative);
        var (secretary, _) = await ClientAs(SystemRoles.Secretary);
        await Reference(rep); // يُنشأ ملف المندوب عند أول دخول.
        var refs = await Reference(secretary);
        var repId = refs.Representatives.Single(r => r.UserId == repUserId).Id;

        var assigned = await Create(secretary, Customer(refs) with { RepresentativeId = repId, RecordDate = new DateOnly(2026, 9, 1) });
        Assert.Equal(repId, assigned.RepresentativeId);
        Assert.Equal(new DateOnly(2026, 9, 1), assigned.RecordDate);
        Assert.Contains(await List(rep), p => p.Id == assigned.Id);
        Assert.Equal(HttpStatusCode.OK, (await rep.GetAsync($"/api/v1/parties/{assigned.Id}")).StatusCode);

        var future = await Post(secretary, "/api/v1/parties", Customer(refs) with { RecordDate = new DateOnly(2100, 1, 1) });
        Assert.Equal(HttpStatusCode.BadRequest, future.StatusCode);
    }

    [Fact]
    public async Task Representative_cannot_choose_owner_or_date()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (other, otherUserId) = await ClientAs(SystemRoles.Representative);
        await Reference(other);
        var refs = await Reference(rep);
        var otherRep = refs.Representatives.Single(r => r.UserId == otherUserId).Id;

        var party = await Create(rep, Customer(refs) with { RepresentativeId = otherRep, RecordDate = new DateOnly(2026, 1, 1) });
        Assert.Equal(refs.MyRepresentativeId, party.RepresentativeId);
        Assert.NotEqual(new DateOnly(2026, 1, 1), party.RecordDate);
        Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);

        var ton = refs.Units.First(u => u.Code == "ton").Id;
        var order = await Read<OrderDto>(await Post(rep, "/api/v1/orders", new CreateOrderRequest(
            Guid.CreateVersion7(), party.Id, new DateOnly(2026, 1, 1), [new LineInput(refs.Materials[0].Id, 1, ton)])));
        Assert.NotEqual(new DateOnly(2026, 1, 1), order.OrderDate);
        // تغيير مرحلة الطلب حدث جديد مسموح للمندوب.
        var stage = await Post(rep, $"/api/v1/orders/{order.Id}/stage", new ChangeStageRequest(OrderStage.Quotation, order.Version));
        Assert.Equal(HttpStatusCode.OK, stage.StatusCode);
    }

    [Fact]
    public async Task Supplier_added_by_a_representative_is_saved_but_hidden_from_them()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(rep);

        var response = await Post(rep, "/api/v1/parties", Supplier(refs));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await Body(response);
        Assert.False(body.GetProperty("visible").GetBoolean());
        var id = body.GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/parties/{id}")).StatusCode);
        Assert.True((await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{id}"))).IsSupplier);
    }

    [Fact]
    public async Task Duplicate_phone_of_a_hidden_record_reveals_nothing()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var phone = UniquePhone();
        await Create(admin, Supplier(refs, phone));

        var duplicate = await Post(rep, "/api/v1/parties", Customer(refs, phone));
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        var body = await Body(duplicate);
        Assert.Equal("party.duplicate_phone_hidden", body.GetProperty("code").GetString());
        Assert.False(body.TryGetProperty("data", out var data) && data.ValueKind != JsonValueKind.Null);
        Assert.DoesNotContain("مورد صلاحيات", body.ToString());
    }

    [Fact]
    public async Task Representative_adds_to_own_customer_but_cannot_edit_or_delete()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(rep);
        var party = await Create(rep, Customer(refs));

        var interest = await Post(rep, $"/api/v1/parties/{party.Id}/interests", new InterestInput(refs.Materials[0].Id));
        Assert.Equal(HttpStatusCode.OK, interest.StatusCode);
        var location = await Post(rep, $"/api/v1/parties/{party.Id}/locations",
            new LocationInput(Guid.CreateVersion7(), LocationKind.Factory, AddressLine: "العاشر من رمضان"));
        Assert.Equal(HttpStatusCode.OK, location.StatusCode);
        var contact = await Post(rep, $"/api/v1/parties/{party.Id}/interactions", new CreateInteractionRequest(
            Guid.CreateVersion7(), ContactChannel.Call, refs.ContactOutcomes.First(o => o.Code == "reached").Id));
        Assert.Equal(HttpStatusCode.OK, contact.StatusCode);

        var detail = await Read<PartyDetail>(await rep.GetAsync($"/api/v1/parties/{party.Id}"));
        // Grade التسجيل + الخامة التي أضافها المندوب.
        Assert.Equal(2, detail.Interests.Count);
        var edit = await rep.PutAsJsonAsync($"/api/v1/parties/{party.Id}", new UpdatePartyRequest(detail.Version, "اسم جديد",
            [new PhoneInput(detail.Phones[0].E164)], detail.CustomerActivityId, RepresentativeId: detail.RepresentativeId), Json);
        Assert.Equal(HttpStatusCode.Forbidden, edit.StatusCode);
        var placeId = (await Read<LocationDto>(location)).Id;
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.DeleteAsync($"/api/v1/locations/{placeId}")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await rep.DeleteAsync($"/api/v1/parties/{party.Id}")).StatusCode);
    }

    [Fact]
    public async Task Admin_deletes_and_restores_and_the_audit_keeps_it()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var (secretary, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(admin);
        var party = await Create(secretary, Customer(refs));

        Assert.Equal(HttpStatusCode.Forbidden, (await secretary.DeleteAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.DeleteAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await secretary.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        Assert.Contains(await List(admin, "deleted=true"), p => p.Id == party.Id);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(secretary, $"/api/v1/parties/{party.Id}/restore", new { })).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await Post(admin, $"/api/v1/parties/{party.Id}/restore", new { })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await secretary.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);

        var audit = await Read<PagedResult<AuditItem>>(await admin.GetAsync($"/api/v1/audit?entityId={party.Id}"));
        Assert.Contains(audit.Items, a => a.Action == "party.deleted");
        Assert.Contains(audit.Items, a => a.Action == "party.restored");
        Assert.Equal(HttpStatusCode.Forbidden, (await secretary.GetAsync("/api/v1/audit")).StatusCode);
    }

    [Theory]
    [InlineData("0101234567", "party.invalid_phone")] // 10 أرقام فقط
    [InlineData("01312345678", "party.invalid_phone")] // بادئة غير موجودة
    [InlineData("01512345678", null)]
    [InlineData("0223456789", "party.invalid_mobile")] // أرضي: لا يصلح رقمًا أساسيًا للعميل
    [InlineData("+966501234567", "party.invalid_mobile")] // دولي: لا يصلح رقمًا أساسيًا للعميل
    public async Task Customer_primary_phone_must_be_an_egyptian_mobile(string phone, string? error)
    {
        var (secretary, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(secretary);
        var response = await Post(secretary, "/api/v1/parties", Customer(refs, phone));
        if (error is null)
            Assert.True(response.StatusCode is HttpStatusCode.Created or HttpStatusCode.Conflict);
        else
            Assert.Equal(error, (await Body(response)).GetProperty("code").GetString());
    }

    [Theory]
    [InlineData("0223456789")]
    [InlineData("+966501234567")]
    public async Task Supplier_phones_may_be_landline_or_international(string phone)
    {
        var (secretary, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(secretary);
        var response = await Post(secretary, "/api/v1/parties", Supplier(refs, phone));
        Assert.True(response.StatusCode is HttpStatusCode.Created or HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task A_customer_needs_at_least_one_material_with_a_grade()
    {
        var (secretary, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(secretary);
        var pvc = refs.Materials.First(m => m.Code == "PVC").Id;
        foreach (var interests in new IReadOnlyList<InterestInput>?[]
                 { null, [], [new InterestInput(pvc)], [new InterestInput(pvc, OpenSpec: true)] })
        {
            var response = await Post(secretary, "/api/v1/parties", Customer(refs) with { Interests = interests });
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal("party.grade_required", (await Body(response)).GetProperty("code").GetString());
        }
        Assert.Equal(HttpStatusCode.Created, (await Post(secretary, "/api/v1/parties", Customer(refs))).StatusCode);
    }

    [Fact]
    public async Task Secretary_assigns_and_the_creator_keeps_access()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (other, otherId) = await ClientAs(SystemRoles.Representative);
        var (secretary, _) = await ClientAs(SystemRoles.Secretary);
        var (outsider, _) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(secretary);
        var party = await Create(rep, Customer(refs));
        await Reference(other); // ينشئ ملف المندوب المرتبط بحسابه.
        var target = (await Reference(secretary)).Representatives.Single(r => r.UserId == otherId);

        var assigned = await Post(secretary, $"/api/v1/parties/{party.Id}/assign", new AssignRequest(target.Id));
        Assert.Equal(HttpStatusCode.OK, assigned.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await rep.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await other.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await outsider.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await Post(rep, $"/api/v1/parties/{party.Id}/assign", new AssignRequest(target.Id))).StatusCode);
        Assert.True((await Read<PartyDetail>(await rep.GetAsync($"/api/v1/parties/{party.Id}"))).Number > 0);
    }

    [Fact]
    public async Task Only_the_admin_replaces_a_saved_logo()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(rep);
        var party = await Create(rep, Customer(refs));
        byte[] png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
        Task<HttpResponseMessage> Logo(string name)
        {
            var file = new ByteArrayContent(png);
            file.Headers.ContentType = new MediaTypeHeaderValue("image/png");
            return rep.PostAsync($"/api/v1/parties/{party.Id}/attachments", new MultipartFormDataContent
            {
                { new StringContent(Guid.CreateVersion7().ToString()), "id" },
                { new StringContent("logo"), "kind" },
                { file, "file", name },
            });
        }

        Assert.Equal(HttpStatusCode.Created, (await Logo("logo.png")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Logo("logo2.png")).StatusCode);
    }

    [Fact]
    public async Task Sales_manager_sees_all_customers_but_no_supplier_data()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (sales, _) = await ClientAs(SystemRoles.SalesManager);
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var customer = await Create(rep, Customer(refs));
        var supplierPhone = UniquePhone();
        var supplier = await Create(admin, Supplier(refs, supplierPhone));

        Assert.Equal(HttpStatusCode.OK, (await sales.GetAsync($"/api/v1/parties/{customer.Id}")).StatusCode);
        Assert.Contains(await List(sales, "role=customer"), p => p.Id == customer.Id);
        Assert.Empty(await List(sales, "role=supplier"));
        Assert.Empty(await List(sales, "q=" + supplierPhone[^6..]));
        Assert.Equal(HttpStatusCode.NotFound, (await sales.GetAsync($"/api/v1/parties/{supplier.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await sales.GetAsync($"/api/v1/parties/{customer.Id}/supplier-matches")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await sales.GetAsync("/api/v1/export/parties?role=supplier")).StatusCode);
    }

    [Fact]
    public async Task Purchasing_manager_sees_all_suppliers_and_only_own_customers()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (purchasing, _) = await ClientAs(SystemRoles.PurchasingManager);
        var refs = await Reference(rep);
        var othersCustomer = await Create(rep, Customer(refs));
        var supplierResponse = await Post(rep, "/api/v1/parties", Supplier(refs));
        var supplierId = (await Body(supplierResponse)).GetProperty("id").GetGuid();
        var own = await Create(purchasing, Customer(refs));

        Assert.Equal(HttpStatusCode.OK, (await purchasing.GetAsync($"/api/v1/parties/{supplierId}")).StatusCode);
        Assert.Contains(await List(purchasing, "role=supplier"), p => p.Id == supplierId);
        var customers = await List(purchasing, "role=customer");
        Assert.Contains(customers, p => p.Id == own.Id);
        Assert.DoesNotContain(customers, p => p.Id == othersCustomer.Id);
        Assert.Equal(HttpStatusCode.NotFound, (await purchasing.GetAsync($"/api/v1/parties/{othersCustomer.Id}")).StatusCode);
    }

    [Fact]
    public async Task Managers_reassign_within_their_scope_and_it_is_audited()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (other, otherUser) = await ClientAs(SystemRoles.Representative);
        var (sales, _) = await ClientAs(SystemRoles.SalesManager);
        var (purchasing, _) = await ClientAs(SystemRoles.PurchasingManager);
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        await Reference(other);
        var refs = await Reference(rep);
        var otherRep = (await Reference(admin)).Representatives.Single(r => r.UserId == otherUser).Id;
        var customer = await Create(rep, Customer(refs));

        Assert.Equal(HttpStatusCode.Forbidden,
            (await Post(rep, $"/api/v1/parties/{customer.Id}/assign", new AssignRequest(otherRep))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await Post(purchasing, $"/api/v1/parties/{customer.Id}/assign", new AssignRequest(otherRep))).StatusCode);
        var assigned = await Read<PartyDetail>(await Post(sales, $"/api/v1/parties/{customer.Id}/assign",
            new AssignRequest(otherRep)));
        Assert.Equal(otherRep, assigned.RepresentativeId);
        // الإسناد لا يمنح تعديل بيانات الشركة.
        var edit = await sales.PutAsJsonAsync($"/api/v1/parties/{customer.Id}", new UpdatePartyRequest(assigned.Version,
            "اسم جديد", [new PhoneInput(assigned.Phones[0].E164)], assigned.CustomerActivityId,
            RepresentativeId: otherRep), Json);
        Assert.Equal(HttpStatusCode.Forbidden, edit.StatusCode);
        // المندوب الجديد يراه الآن.
        Assert.Equal(HttpStatusCode.OK, (await other.GetAsync($"/api/v1/parties/{customer.Id}")).StatusCode);

        var audit = await Read<PagedResult<AuditItem>>(await admin.GetAsync($"/api/v1/audit?entityId={customer.Id}"));
        Assert.Contains(audit.Items, a => a.Action == "party.assigned");
    }
}
