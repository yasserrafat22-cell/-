using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>
/// دفعة الإصلاحات 02: نشاط العميل (كتالوج مركزي واختيار متعدد اختياري)، رقم هاتف موظف العميل،
/// وصورة العميل في بطاقات «السجل».
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class Batch02ApiTests(ApiFactory api)
{
    private const string Password = "Crm12345a";
    private static readonly byte[] Png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

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

    private static async Task<string?> Code(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.GetProperty("code").GetString();

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static async Task<ReferenceBundle> Reference(HttpClient client) =>
        await Read<ReferenceBundle>(await client.GetAsync("/api/v1/reference"));

    private static CreatePartyRequest Customer(string name, IReadOnlyList<Guid>? activities = null) =>
        new(Guid.CreateVersion7(), $"{name} {Guid.NewGuid():N}"[..(name.Length + 9)], true, false,
            [new PhoneInput(UniquePhone())],
            Interests: ApiFactory.FixtureInterests, CustomerActivityIds: activities);

    private static async Task<PartyDetail> Create(HttpClient client, CreatePartyRequest request)
    {
        var response = await Post(client, "/api/v1/parties", request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await Read<PartyDetail>(response);
    }

    [Fact]
    public async Task Initial_customer_activities_are_seeded_in_owner_order_with_other_last()
    {
        var refs = await Reference(await ClientAs(SystemRoles.Representative));
        var names = refs.CustomerActivities!.Select(a => a.Name).ToList();
        foreach (var expected in new[] { "حقن البلاستيك", "نفخ البلاستيك", "سحب الأفلام", "تصنيع الأكياس والشنط",
                     "تصنيع المواسير", "التعبئة والتغليف", "إعادة تدوير البلاستيك", "بثق البلاستيك", "تصنيع العبوات",
                     "تجارة الخامات" })
            Assert.Contains(expected, names);
        Assert.Equal("أخرى", names[^1]);
        Assert.True(names.IndexOf("حقن البلاستيك") < names.IndexOf("تجارة الخامات"));
    }

    [Fact]
    public async Task A_new_activity_joins_the_central_catalog_once_after_normalization()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var name = $"تشكيل حراري {Guid.NewGuid():N}"[..20];
        var created = await Post(rep, "/api/v1/catalog/customer-activities", new { name });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var activity = await Read<CustomerActivityDto>(created);

        // مسافات زائدة وحروف بديلة (ة/ه، أ/ا) لا تنشئ نشاطًا ثانيًا.
        var variant = "  " + name.Replace("ي", "ى").Replace(" ", "   ") + " ";
        var again = await Post(await ClientAs(SystemRoles.Secretary), "/api/v1/catalog/customer-activities",
            new { name = variant });
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
        Assert.Equal(activity.Id, (await Read<CustomerActivityDto>(again)).Id);

        var refs = await Reference(rep);
        Assert.Single(refs.CustomerActivities!, a => a.Id == activity.Id);
        Assert.Equal("activity.invalid_name",
            await Code(await Post(rep, "/api/v1/catalog/customer-activities", new { name = " " })));
    }

    [Fact]
    public async Task Activities_are_optional_saved_returned_and_replaced_only_when_sent()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var (injection, blowing, recycling) = (refs.CustomerActivities![0].Id, refs.CustomerActivities[1].Id,
            refs.CustomerActivities[6].Id);

        // بدون نشاط: يُحفظ العميل كالمعتاد (ليس شرطًا جديدًا).
        var plain = await Create(admin, Customer("عميل بلا نشاط"));
        Assert.Empty(plain.CustomerActivityIds ?? []);

        var party = await Create(admin, Customer("عميل بنشاطين", [blowing, injection, injection]));
        Assert.Equal([injection, blowing], party.CustomerActivityIds);
        Assert.Equal([injection, blowing], (await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{party.Id}")))
            .CustomerActivityIds);

        // تعديل لا يرسل الأنشطة (نسخة تطبيق سابقة): لا تتغير.
        var update = new UpdatePartyRequest(party.Version, party.Name,
            [new PhoneInput(party.Phones[0].E164)], Email: "a@b.co");
        var kept = await Read<PartyDetail>(await admin.PutAsJsonAsync($"/api/v1/parties/{party.Id}", update, Json));
        Assert.Equal([injection, blowing], kept.CustomerActivityIds);

        var replaced = await Read<PartyDetail>(await admin.PutAsJsonAsync($"/api/v1/parties/{party.Id}",
            update with { Version = kept.Version, CustomerActivityIds = [recycling] }, Json));
        Assert.Equal([recycling], replaced.CustomerActivityIds);

        var unknown = await Post(admin, "/api/v1/parties", Customer("عميل بنشاط مجهول", [Guid.CreateVersion7()]));
        Assert.Equal("party.unknown_activity", await Code(unknown));
    }

    [Fact]
    public async Task Registry_filters_and_searches_by_activity_within_the_users_scope()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var other = await ClientAs(SystemRoles.Representative);
        var refs = await Reference(rep);
        var name = $"نشاط بحث {Guid.NewGuid():N}"[..18];
        var activity = await Read<CustomerActivityDto>(
            await Post(rep, "/api/v1/catalog/customer-activities", new { name }));
        var mine = await Create(rep, Customer("عميل نشاط السجل", [activity.Id]));
        var theirs = await Create(other, Customer("عميل مندوب آخر", [activity.Id]));
        var none = await Create(rep, Customer("عميل بلا نشاط في السجل"));

        var filtered = await Read<PagedResult<RegistryItem>>(
            await rep.GetAsync($"/api/v1/parties?role=customer&activityId={activity.Id}&take=50"));
        Assert.Contains(filtered.Items, i => i.Id == mine.Id && i.CustomerActivityIds!.Contains(activity.Id));
        Assert.DoesNotContain(filtered.Items, i => i.Id == theirs.Id); // نطاق المندوب كما هو
        Assert.DoesNotContain(filtered.Items, i => i.Id == none.Id);

        var searched = await Read<PagedResult<RegistryItem>>(
            await rep.GetAsync($"/api/v1/parties?role=customer&q={Uri.EscapeDataString(name)}&take=50"));
        Assert.Contains(searched.Items, i => i.Id == mine.Id);
        Assert.DoesNotContain(searched.Items, i => i.Id == theirs.Id);
        _ = refs;
    }

    [Fact]
    public async Task Report_dashboard_narrows_customer_figures_to_an_activity()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var name = $"نشاط تقرير {Guid.NewGuid():N}"[..20];
        var activity = await Read<CustomerActivityDto>(
            await Post(admin, "/api/v1/catalog/customer-activities", new { name }));
        await Create(admin, Customer("عميل نشاط التقرير", [activity.Id]));
        await Create(admin, Customer("عميل بلا نشاط التقرير"));

        // فترة صريحة تشمل وقت الإنشاء (حدود اليوم بتوقيت العمل قد تختلف عن UTC).
        var from = DateTime.UtcNow.AddDays(-2).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
        var dashboard = JsonDocument.Parse(await (await admin.GetAsync(
                $"/api/v1/reports/dashboard?from={from}&activityId={activity.Id}")).Content.ReadAsStringAsync())
            .RootElement;
        Assert.Equal(1, dashboard.GetProperty("kpis").GetProperty("newCustomers").GetInt32());
        var all = JsonDocument.Parse(await (await admin.GetAsync($"/api/v1/reports/dashboard?from={from}"))
            .Content.ReadAsStringAsync()).RootElement;
        Assert.True(all.GetProperty("kpis").GetProperty("newCustomers").GetInt32() >= 2);
    }

    [Fact]
    public async Task Registry_card_carries_the_company_logo_only_not_other_attachments()
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var outsider = await ClientAs(SystemRoles.Representative);
        var withLogo = await Create(rep, Customer("عميل بصورة"));
        var withFileOnly = await Create(rep, Customer("عميل بمرفق فقط"));

        async Task<Guid> Upload(Guid partyId, string kind)
        {
            var file = new ByteArrayContent(Png);
            file.Headers.ContentType = new MediaTypeHeaderValue("image/png");
            var id = Guid.CreateVersion7();
            Assert.Equal(HttpStatusCode.Created, (await rep.PostAsync($"/api/v1/parties/{partyId}/attachments",
                new MultipartFormDataContent
                {
                    { new StringContent(id.ToString()), "id" },
                    { new StringContent(kind), "kind" },
                    { file, "file", "photo.png" },
                })).StatusCode);
            return id;
        }

        var logoId = await Upload(withLogo.Id, "logo");
        await Upload(withLogo.Id, "other");
        await Upload(withFileOnly.Id, "other");

        var page = await Read<PagedResult<RegistryItem>>(await rep.GetAsync("/api/v1/parties?role=customer&take=50"));
        Assert.Equal(logoId, page.Items.Single(i => i.Id == withLogo.Id).LogoAttachmentId);
        Assert.Null(page.Items.Single(i => i.Id == withFileOnly.Id).LogoAttachmentId);

        // الصورة نفسها بصلاحيات المرفقات: من لا يرى العميل لا يحصل عليها.
        Assert.Equal(HttpStatusCode.OK, (await rep.GetAsync($"/api/v1/attachments/{logoId}/content")).StatusCode);
        Assert.NotEqual(HttpStatusCode.OK, (await outsider.GetAsync($"/api/v1/attachments/{logoId}/content")).StatusCode);
    }

    [Theory]
    [InlineData("0155566", "party.invalid_phone")] // ناقص: لم يعد يُقبل
    [InlineData("01312345678", "party.invalid_phone")] // بادئة غير موجودة
    [InlineData("0223456789", "contact.invalid_mobile")] // أرضي: لا يصلح لموظف العميل
    [InlineData("+966501234567", "contact.invalid_mobile")] // دولي: لا يصلح لموظف العميل
    [InlineData("01012345678", null)]
    [InlineData("", null)] // الرقم اختياري
    public async Task Customer_employee_phone_follows_the_primary_phone_rule(string mobile, string? error)
    {
        var rep = await ClientAs(SystemRoles.Representative);
        var party = await Create(rep, Customer("عميل موظفين"));
        var response = await Post(rep, $"/api/v1/parties/{party.Id}/contacts",
            new ContactInput(Guid.CreateVersion7(), "موظف", "مدير مشتريات", mobile));
        if (error is null)
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        else
            Assert.Equal(error, await Code(response));
    }

    [Fact]
    public async Task Supplier_contacts_keep_landline_and_international_numbers()
    {
        var admin = await ClientAs(SystemRoles.SystemAdmin);
        var refs = await Reference(admin);
        var supplier = await Create(admin, new CreatePartyRequest(Guid.CreateVersion7(), $"مورد دولي {Guid.NewGuid():N}", false, true,
            [new PhoneInput(UniquePhone())], SupplierActivityId: refs.ActivityTypes.First(a => a.Code == "factory").Id));
        foreach (var mobile in new[] { "0223456789", "+966501234567" })
            Assert.Equal(HttpStatusCode.OK, (await Post(admin, $"/api/v1/parties/{supplier.Id}/contacts",
                new ContactInput(Guid.CreateVersion7(), "جهة اتصال", null, mobile))).StatusCode);
    }
}
