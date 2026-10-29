using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

[Collection(DatabaseCollection.Name)]
public sealed class CrmApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string Unique(string prefix) => $"{prefix}_{Guid.NewGuid():N}"[..20];

    /// <summary>رقم هاتف مصري فريد لكل اختبار حتى لا تتعارض الاختبارات.</summary>
    private static string UniquePhone() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private async Task<(HttpClient Client, Guid UserId)> ClientAs(string role)
    {
        var username = Unique(role[..3]);
        var userId = await api.CreateUserAsync(username, Password, role);
        var session = await api.LoginAsync(username, Password);
        return (api.CreateClient(session.AccessToken), userId);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Json))!;

    private static async Task<string?> Code(HttpResponseMessage response)
    {
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.TryGetProperty("code", out var c) ? c.GetString() : null;
    }

    private static async Task<ReferenceBundle> Reference(HttpClient client) =>
        await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));

    private static Task<HttpResponseMessage> PostJson(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static CreatePartyRequest Customer(ReferenceBundle refs, string? phone = null, string name = "شركة النور للصناعات البلاستيكية") =>
        new(Guid.CreateVersion7(), name, IsCustomer: true, IsSupplier: false,
            [new PhoneInput(phone ?? UniquePhone())],
            CustomerActivityId: refs.ActivityTypes.First(a => a.Code == "factory").Id,
            Interests:
            [
                new InterestInput(refs.Materials.First(m => m.Code == "PVC").Id, "SG-5"),
                new InterestInput(refs.Materials.First(m => m.Code == "HDPE").Id),
            ]);

    private static CreatePartyRequest Supplier(ReferenceBundle refs, string grade = "SG-5") =>
        new(Guid.CreateVersion7(), "شركة الصفوة لمواد البلاستيك", IsCustomer: false, IsSupplier: true,
            [new PhoneInput(UniquePhone())],
            SupplierActivityId: refs.ActivityTypes.First(a => a.Code == "importer").Id,
            Products: [new ProductInput(refs.Materials.First(m => m.Code == "PVC").Id, grade)]);

    private static async Task<PartyDetail> CreateParty(HttpClient client, CreatePartyRequest request)
    {
        var response = await PostJson(client, "/api/v1/parties", request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await Read<PartyDetail>(response);
    }

    [Fact]
    public async Task Reference_bundle_has_seeded_lists_and_my_representative()
    {
        var (client, userId) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(client);

        Assert.Contains(refs.Materials, m => m.Code == "PVC");
        Assert.Contains(refs.Units, u => u.Code == "ton" && u.FactorToKg == 1000);
        Assert.Contains(refs.ActivityTypes, a => a.NameAr == "مصنع");
        Assert.Contains(refs.ContactOutcomes, o => o.Semantic == "reached");
        Assert.Equal(27, refs.Governorates.Count);
        Assert.Contains(refs.Representatives, r => r.UserId == userId && r.Id == refs.MyRepresentativeId);
    }

    [Fact]
    public async Task Quick_customer_registration_normalizes_phone_and_derives_summary()
    {
        var (client, _) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(client);
        var phone = UniquePhone();

        var party = await CreateParty(client, Customer(refs, phone));

        Assert.Equal("+20" + phone[1..], party.Phones.Single().E164);
        Assert.Equal(refs.MyRepresentativeId, party.RepresentativeId);
        Assert.Equal(["PVC", "HDPE"], party.Interests.Select(i => i.MaterialCode).Order(StringComparer.Ordinal).Reverse());
        Assert.Equal("SG-5", party.Interests.Single(i => i.MaterialCode == "PVC").GradeCode);
        // المندوب يضيف ولا يعدّل المحفوظ.
        Assert.False(party.CanEdit);
        Assert.True(party.CanAdd);
        Assert.NotNull(party.RecordDate);
        Assert.Equal(PartyStatus.New, party.CustomerSummary!.Status);
        Assert.Null(party.CustomerSummary.LastDealDate);
        Assert.Null(party.CustomerSummary.LastContactAt);
        Assert.Null(party.SupplierSummary);
    }

    [Fact]
    public async Task Resending_the_same_registration_does_not_duplicate()
    {
        var (client, _) = await ClientAs(SystemRoles.Representative);
        var request = Customer(await Reference(client));

        var first = await PostJson(client, "/api/v1/parties", request);
        var retry = await PostJson(client, "/api/v1/parties", request);

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
        Assert.Equal(1, await api.WithDbAsync(db => db.Parties.CountAsync(p => p.Id == request.Id)));
    }

    [Fact]
    public async Task Duplicate_phone_is_rejected_and_the_company_can_take_a_second_role()
    {
        var (rep, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(rep);
        var phone = UniquePhone();
        var customer = await CreateParty(rep, Customer(refs, phone));

        var duplicate = await PostJson(rep, "/api/v1/parties", Supplier(refs) with { Phones = [new PhoneInput("+2" + phone)] });
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        using (var doc = JsonDocument.Parse(await duplicate.Content.ReadAsStringAsync()))
        {
            Assert.Equal("party.duplicate_phone", doc.RootElement.GetProperty("code").GetString());
            Assert.Equal(customer.Id, doc.RootElement.GetProperty("data").GetProperty("partyId").GetGuid());
        }

        var both = await Read<PartyDetail>(await PostJson(rep, $"/api/v1/parties/{customer.Id}/roles",
            new AddRoleRequest(false, true, SupplierActivityId: refs.ActivityTypes.First(a => a.Code == "trader").Id)));
        Assert.True(both.IsCustomer);
        Assert.True(both.IsSupplier);
        Assert.NotNull(both.SupplierSummary);
    }

    [Fact]
    public async Task Invalid_input_is_rejected_with_a_clear_code()
    {
        var (client, _) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(client);

        var badPhone = await PostJson(client, "/api/v1/parties", Customer(refs) with { Phones = [new PhoneInput("123")] });
        var noRole = await PostJson(client, "/api/v1/parties", Customer(refs) with { IsCustomer = false });
        var noName = await PostJson(client, "/api/v1/parties", Customer(refs) with { Name = " " });

        Assert.Equal("party.invalid_phone", await Code(badPhone));
        Assert.Equal(HttpStatusCode.BadRequest, noRole.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, noName.StatusCode);
    }

    [Fact]
    public async Task Only_the_admin_edits_saved_records()
    {
        var (repA, _) = await ClientAs(SystemRoles.Representative);
        var (repB, _) = await ClientAs(SystemRoles.Representative);
        var (manager, _) = await ClientAs(SystemRoles.SalesManager);
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(repA);
        var party = await CreateParty(repA, Customer(refs));
        UpdatePartyRequest Update(uint version, string name) =>
            new(version, name, [new PhoneInput(party.Phones[0].E164)], party.CustomerActivityId,
                RepresentativeId: party.RepresentativeId);

        // مندوب آخر لا يرى العميل أصلًا.
        Assert.Equal(HttpStatusCode.NotFound, (await repB.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        var editByB = await repB.PutAsJsonAsync($"/api/v1/parties/{party.Id}", Update(party.Version, "تعديل غير مسموح"), Json);
        Assert.Equal(HttpStatusCode.NotFound, editByB.StatusCode);

        // صاحب السجل ومدير المبيعات لا يعدّلان ولا يحذفان.
        foreach (var client in new[] { repA, manager })
        {
            var view = await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{party.Id}"));
            Assert.False(view.CanEdit);
            var edit = await client.PutAsJsonAsync($"/api/v1/parties/{party.Id}", Update(party.Version, "تعديل غير مسموح"), Json);
            Assert.Equal(HttpStatusCode.Forbidden, edit.StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await client.DeleteAsync($"/api/v1/parties/{party.Id}")).StatusCode);
        }

        var editByAdmin = await admin.PutAsJsonAsync($"/api/v1/parties/{party.Id}", Update(party.Version, "اسم معدل من المدير"), Json);
        Assert.Equal(HttpStatusCode.OK, editByAdmin.StatusCode);

        using var anonymous = api.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync($"/api/v1/parties/{party.Id}")).StatusCode);
    }

    [Fact]
    public async Task Concurrent_edit_is_detected_instead_of_silently_overwritten()
    {
        var (client, _) = await ClientAs(SystemRoles.SystemAdmin);
        var party = await CreateParty(client, Customer(await Reference(client)));
        UpdatePartyRequest Update(uint version, string notes) =>
            new(version, party.Name, [new PhoneInput(party.Phones[0].E164)], party.CustomerActivityId,
                RepresentativeId: party.RepresentativeId, Notes: notes, Email: "info@example.com");

        var first = await client.PutAsJsonAsync($"/api/v1/parties/{party.Id}", Update(party.Version, "من الجهاز الأول"), Json);
        var second = await client.PutAsJsonAsync($"/api/v1/parties/{party.Id}", Update(party.Version, "من الجهاز الثاني"), Json);

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
        Assert.Equal("concurrency.stale", await Code(second));
        var current = await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{party.Id}"));
        Assert.Equal("من الجهاز الأول", current.Notes);
        Assert.Equal("info@example.com", current.Email);
        Assert.NotEqual(party.Version, current.Version);
    }

    [Fact]
    public async Task Orders_follow_stage_rules_and_only_purchases_count_as_last_order()
    {
        // السكرتارية تحدد التاريخ عند الإدخال (المندوب يُثبت له تاريخ اليوم).
        var (client, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(client);
        var customer = await CreateParty(client, Customer(refs));
        var pvc = refs.Materials.First(m => m.Code == "PVC").Id;
        var ton = refs.Units.First(u => u.Code == "ton").Id;
        var kg = refs.Units.First(u => u.Code == "kg").Id;

        var created = await PostJson(client, "/api/v1/orders", new CreateOrderRequest(Guid.CreateVersion7(), customer.Id,
            new DateOnly(2026, 10, 27), [new LineInput(pvc, 3, ton, "SG5"), new LineInput(pvc, 500, kg)]));
        Assert.Equal(HttpStatusCode.OK, created.StatusCode);
        var order = await Read<OrderDto>(created);
        Assert.Equal(OrderStage.Inquiry, order.Stage);
        Assert.Equal(3500m, order.TotalKg);
        Assert.Equal("SG-5", order.Lines[0].GradeCode);

        var afterInquiry = await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{customer.Id}"));
        Assert.Null(afterInquiry.CustomerSummary!.LastDealDate);

        var confirmed = await Read<OrderDto>(await PostJson(client, $"/api/v1/orders/{order.Id}/stage",
            new ChangeStageRequest(OrderStage.Confirmed, order.Version)));
        Assert.Equal(OrderStage.Confirmed, confirmed.Stage);

        var stale = await PostJson(client, $"/api/v1/orders/{order.Id}/stage", new ChangeStageRequest(OrderStage.Completed, order.Version));
        Assert.Equal("concurrency.stale", await Code(stale));

        var onHold = await Read<OrderDto>(await PostJson(client, $"/api/v1/orders/{order.Id}/hold", new SetHoldRequest(true, confirmed.Version)));
        Assert.True(onHold.OnHold);
        var completed = await Read<OrderDto>(await PostJson(client, $"/api/v1/orders/{order.Id}/stage",
            new ChangeStageRequest(OrderStage.Completed, onHold.Version)));
        Assert.False(completed.OnHold);

        var backwards = await PostJson(client, $"/api/v1/orders/{order.Id}/stage", new ChangeStageRequest(OrderStage.Inquiry, completed.Version));
        Assert.Equal("order.invalid_transition", await Code(backwards));

        var summary = (await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{customer.Id}"))).CustomerSummary!;
        Assert.Equal(new DateOnly(2026, 10, 27), summary.LastDealDate);
        Assert.Equal(3500m, summary.LastDealQuantityKg);
        Assert.Equal(1, await api.WithDbAsync(db => db.OrderStageChanges.CountAsync(c => c.OrderId == order.Id && c.ToStage == OrderStage.Completed)));
    }

    [Fact]
    public async Task Contacts_drive_last_contact_and_follow_up_status()
    {
        // السكرتارية تحدد التاريخ عند الإدخال (المندوب يُثبت له تاريخ اليوم).
        var (client, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(client);
        var customer = await CreateParty(client, Customer(refs));
        var reached = refs.ContactOutcomes.First(o => o.Code == "reached").Id;
        var supplierOnly = refs.ContactOutcomes.First(o => o.Code == "follow_up_agreed").Id;
        var now = DateTimeOffset.UtcNow;

        var wrongOutcome = await PostJson(client, $"/api/v1/parties/{customer.Id}/interactions",
            new CreateInteractionRequest(Guid.CreateVersion7(), ContactChannel.Call, supplierOnly));
        Assert.Equal(HttpStatusCode.BadRequest, wrongOutcome.StatusCode);

        var withDueFollowUp = await PostJson(client, $"/api/v1/parties/{customer.Id}/interactions",
            new CreateInteractionRequest(Guid.CreateVersion7(), ContactChannel.WhatsApp, reached,
                OccurredAt: now.AddDays(-3), NextFollowUpAt: now.AddDays(-1), Remind: true));
        Assert.Equal(HttpStatusCode.OK, withDueFollowUp.StatusCode);
        var due = (await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{customer.Id}"))).CustomerSummary!;
        Assert.Equal(PartyStatus.NeedsFollowUp, due.Status);

        await PostJson(client, $"/api/v1/parties/{customer.Id}/interactions",
            new CreateInteractionRequest(Guid.CreateVersion7(), ContactChannel.Call, reached, NextFollowUpAt: now.AddDays(7)));
        var after = (await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{customer.Id}"))).CustomerSummary!;
        Assert.Equal(PartyStatus.New, after.Status);
        Assert.True(after.LastContactAt > now.AddMinutes(-1));
        Assert.True(after.NextFollowUpAt > now.AddDays(6));

        var history = await Read<List<InteractionDto>>(await client.GetAsync($"/api/v1/parties/{customer.Id}/interactions"));
        Assert.Equal(2, history.Count);
        Assert.True(history[1].FollowUpDone);
        Assert.Equal("تم التواصل بنجاح", history[0].OutcomeName);
    }

    [Fact]
    public async Task Supplier_products_share_normalized_grades_and_supplies_update_summary()
    {
        // السكرتارية تحدد التاريخ عند الإدخال (المندوب يُثبت له تاريخ اليوم).
        var (client, _) = await ClientAs(SystemRoles.Secretary);
        var refs = await Reference(client);
        var first = await CreateParty(client, Supplier(refs, "K-67"));
        var second = await CreateParty(client, Supplier(refs, "k67"));
        Assert.Equal(first.Products[0].GradeId, second.Products[0].GradeId);
        Assert.Equal("K-67", second.Products[0].GradeCode);

        var pvc = refs.Materials.First(m => m.Code == "PVC").Id;
        var ton = refs.Units.First(u => u.Code == "ton").Id;
        var expected = await Read<SupplyDto>(await PostJson(client, "/api/v1/supplies", new CreateSupplyRequest(
            Guid.CreateVersion7(), first.Id, new DateOnly(2026, 10, 15), [new LineInput(pvc, 5, ton)], SupplyStatus.Expected)));
        var beforeReceipt = (await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{first.Id}"))).SupplierSummary!;
        Assert.Null(beforeReceipt.LastDealDate);

        await PostJson(client, $"/api/v1/supplies/{expected.Id}/status", new ChangeSupplyStatusRequest(SupplyStatus.Received, expected.Version));
        var summary = (await Read<PartyDetail>(await client.GetAsync($"/api/v1/parties/{first.Id}"))).SupplierSummary!;
        Assert.Equal(new DateOnly(2026, 10, 15), summary.LastDealDate);
        Assert.Equal(5000m, summary.LastDealQuantityKg);

        var orderForSupplier = await PostJson(client, "/api/v1/orders", new CreateOrderRequest(Guid.CreateVersion7(), first.Id,
            new DateOnly(2026, 10, 27), [new LineInput(pvc, 1, ton)]));
        Assert.Equal(HttpStatusCode.BadRequest, orderForSupplier.StatusCode);
    }

    [Fact]
    public async Task Prices_are_protected_and_history_is_kept()
    {
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (purchasing, _) = await ClientAs(SystemRoles.PurchasingManager);
        var refs = await Reference(purchasing);
        var supplier = await CreateParty(purchasing, Supplier(refs));
        var productId = supplier.Products[0].Id;
        var ton = refs.Units.First(u => u.Code == "ton").Id;

        var old = await PostJson(purchasing, $"/api/v1/supplier-products/{productId}/quotes", new CreateQuoteRequest(
            Guid.CreateVersion7(), 41000, "egp", ton, new DateOnly(2026, 9, 1), ValidUntil: new DateOnly(2026, 9, 15)));
        Assert.Equal(HttpStatusCode.OK, old.StatusCode);
        await PostJson(purchasing, $"/api/v1/supplier-products/{productId}/quotes", new CreateQuoteRequest(
            Guid.CreateVersion7(), 42000, "EGP", ton, new DateOnly(2026, 10, 22), TransportNote: "شامل النقل"));

        var quotes = await Read<List<QuoteDto>>(await purchasing.GetAsync($"/api/v1/supplier-products/{productId}/quotes"));
        Assert.Equal([42000m, 41000m], quotes.Select(q => q.Price));
        Assert.True(quotes[1].Expired);
        var latest = (await Read<PartyDetail>(await purchasing.GetAsync($"/api/v1/parties/{supplier.Id}"))).Products[0].LatestPrice!;
        Assert.Equal(42000m, latest.Price);

        Assert.Equal(HttpStatusCode.Forbidden, (await rep.GetAsync($"/api/v1/supplier-products/{productId}/quotes")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await PostJson(rep, $"/api/v1/supplier-products/{productId}/quotes",
            new CreateQuoteRequest(Guid.CreateVersion7(), 1, "EGP", ton, new DateOnly(2026, 10, 1)))).StatusCode);
        // المندوب لا يرى الموردين إطلاقًا.
        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/parties/{supplier.Id}")).StatusCode);
    }

    [Fact]
    public async Task List_filters_by_role_and_matches_arabic_spelling_variants()
    {
        var (client, _) = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(client);
        var marker = Guid.NewGuid().ToString("N")[..6];
        var customer = await CreateParty(client, Customer(refs, name: $"شركة الأمل {marker}"));
        var supplier = await CreateParty(client, Supplier(refs) with { Name = $"مورد الأمل {marker}" });

        var customers = await Read<PagedResult<PartyListItem>>(await client.GetAsync($"/api/v1/parties?role=customer&q=الامل {marker}"));
        Assert.Contains(customers.Items, p => p.Id == customer.Id);
        Assert.DoesNotContain(customers.Items, p => p.Id == supplier.Id);

        var byPhone = await Read<PagedResult<PartyListItem>>(await client.GetAsync($"/api/v1/parties?q={Uri.EscapeDataString(customer.Phones[0].E164)}"));
        Assert.Equal(customer.Id, byPhone.Items.Single().Id);
    }

    [Fact]
    public async Task Changes_are_audited()
    {
        var (client, userId) = await ClientAs(SystemRoles.Representative);
        var party = await CreateParty(client, Customer(await Reference(client)));

        var audit = await api.WithDbAsync(db => db.AuditEntries
            .Where(a => a.EntityId == party.Id).Select(a => new { a.Action, a.UserId }).ToListAsync());
        Assert.Contains(audit, a => a.Action == "party.created" && a.UserId == userId);
    }

    [Fact]
    public async Task Version_endpoint_reports_the_applied_schema()
    {
        using var client = api.CreateClient();
        using var doc = JsonDocument.Parse(await client.GetStringAsync("/api/v1/version"));
        using var scope = api.Services.CreateScope();
        var latest = scope.ServiceProvider.GetRequiredService<Qadisiyah.Infrastructure.Persistence.AppDbContext>()
            .Database.GetMigrations().Last();
        Assert.Equal(latest, doc.RootElement.GetProperty("schema").GetString());
        Assert.Equal("0.4.0", doc.RootElement.GetProperty("version").GetString());
    }
}
