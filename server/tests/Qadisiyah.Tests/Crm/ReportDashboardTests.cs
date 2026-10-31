using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>لوحة التقارير: المكتمل مبيعات محققة والمفتوح والملغى منفصلان، وكل رقم ضمن صلاحيات المستخدم.</summary>
[Collection(DatabaseCollection.Name)]
public sealed class ReportDashboardTests(ApiFactory api)
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

    private static async Task<PartyDetail> Customer(HttpClient client, string name) =>
        await Read<PartyDetail>(await Post(client, "/api/v1/parties", new CreatePartyRequest(Guid.CreateVersion7(),
            name, true, false, [new PhoneInput(UniquePhone())], Interests: ApiFactory.FixtureInterests, ConfirmSimilar: true)));

    private static async Task Order(HttpClient client, Guid customer, DateOnly date, decimal kg, OrderStage stage,
        ReferenceBundle refs, Guid? grade = null)
    {
        var pp = refs.Materials.First(m => m.Code == "PP").Id;
        var unit = refs.Units.First(u => u.Code == "kg").Id;
        var response = await Post(client, "/api/v1/orders", new CreateOrderRequest(Guid.CreateVersion7(), customer, date,
            [new LineInput(pp, kg, unit, GradeId: grade)], stage));
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
    }

    private static Task<ReportDashboard> Dashboard(HttpClient client, string query) =>
        client.GetFromJsonAsync<ReportDashboard>("/api/v1/reports/dashboard?" + query, Json)!;

    [Fact]
    public async Task Completed_orders_are_sales_and_open_or_cancelled_are_separate()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var customer = await Customer(admin, $"عميل تقرير {Guid.NewGuid():N}"[..20]);
        var march = new DateOnly(2026, 3, 10);
        await Order(admin, customer.Id, march, 2000, OrderStage.Completed, refs);
        await Order(admin, customer.Id, march.AddDays(2), 500, OrderStage.Inquiry, refs);
        await Order(admin, customer.Id, march.AddDays(5), 300, OrderStage.Cancelled, refs);
        await Order(admin, customer.Id, new DateOnly(2026, 2, 5), 1000, OrderStage.Completed, refs);

        var d = await Dashboard(admin, $"from=2026-03-01&to=2026-03-31&customerId={customer.Id}");
        Assert.Equal(new DashboardKpis(1, 2000, 1, 500, 1, 300, 1, d.Kpis.NewCustomers, d.Kpis.Contacts, 0.5m, false),
            d.Kpis);
        Assert.Equal(2000, d.Pipeline.Single(p => p.Stage == "Completed").Kg);
        Assert.Equal(500, d.Pipeline.Single(p => p.Stage == "Inquiry").Kg);
        Assert.Equal("PP", d.Materials.Single().Label);
        Assert.Equal(customer.Id, d.Customers.Single().Id);
        Assert.Equal(6, d.Trend.Count);
        Assert.Equal(1000, d.Trend.Single(t => t.Month == "2026-02").Kg);
        Assert.Equal(2000, d.Trend.Single(t => t.Month == "2026-03").Kg);
        Assert.NotNull(d.Quality);

        // الافتراضي: الشهر الحالي.
        var current = await Dashboard(admin, "");
        Assert.NotNull(current.Suppliers);
        Assert.Equal(1, current.From.Day);
        Assert.Equal(current.To.Month, current.From.Month);

        var excel = await admin.GetAsync($"/api/v1/reports/dashboard/excel?from=2026-03-01&to=2026-03-31&customerId={customer.Id}&sections=kpis,materials");
        Assert.Equal(HttpStatusCode.OK, excel.StatusCode);
        var rows = XlsxReader.Read(await excel.Content.ReadAsStreamAsync());
        Assert.Contains(rows, r => r.Length > 1 && r[1] == "طلبات مكتملة (مبيعات محققة)" && r[3] == "2000");
        Assert.DoesNotContain(rows, r => r.Length > 0 && r[0] == "أعلى العملاء");
    }

    [Fact]
    public async Task Each_role_sees_only_its_own_scope_and_reps_cannot_export_reports()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var rep = await ClientAs(SystemRoles.Representative);
        var sales = await ClientAs(SystemRoles.SalesManager);
        var refs = (await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json))!;
        var mine = await Customer(rep, $"عميل المندوب {Guid.NewGuid():N}"[..22]);
        var other = await Customer(admin, $"عميل آخر {Guid.NewGuid():N}"[..20]);
        // تاريخ طلب المندوب دائمًا اليوم؛ نافذة حول اليوم تكفي.
        var day = DateOnly.FromDateTime(DateTime.UtcNow);
        var range = $"from={day.AddDays(-3):yyyy-MM-dd}&to={day.AddDays(3):yyyy-MM-dd}";
        await Order(rep, mine.Id, day, 700, OrderStage.Completed, refs);
        await Order(admin, other.Id, day, 9000, OrderStage.Completed, refs);

        var repView = await Dashboard(rep, range);
        Assert.Equal(700, repView.Kpis.CompletedKg);
        Assert.Equal([mine.Id], repView.Customers.Select(c => c.Id!.Value));
        Assert.Null(repView.Suppliers);
        Assert.Null(repView.Quality);
        Assert.All(repView.Demand, x => Assert.Null(x.Suppliers));

        var salesView = await Dashboard(sales, range);
        Assert.Contains(salesView.Customers, c => c.Id == other.Id);
        Assert.Null(salesView.Suppliers);

        // المندوب لا يرى بيانات عميل غيره حتى بتحديده صراحة.
        var probe = await Dashboard(rep, $"{range}&customerId={other.Id}");
        Assert.Equal(0, probe.Kpis.CompletedOrders);
        Assert.Empty(probe.Customers);

        Assert.Equal(HttpStatusCode.Forbidden,
            (await rep.GetAsync("/api/v1/reports/dashboard/excel?" + range)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await Post(rep, "/api/v1/share/authorize", new ShareRequest("report.pdf", 1))).StatusCode);
        Assert.Equal(HttpStatusCode.OK,
            (await Post(sales, "/api/v1/share/authorize", new ShareRequest("report.text", 1))).StatusCode);
    }
}
