using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>
/// الإدخال السريع 0.7.0 — المرحلة 3: تنظيف «بانتظار الاستكمال» باستبعاد منطقي فقط (فردي، مجموعة، كل
/// المؤهل بمعاينة ورمز لقطة)، مع حماية المكتمل والمرتبط والإنشاء غير المؤكد، والصلاحيات لكل صف.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class QuickEntryPhase3Tests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string Mobile() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private async Task<HttpClient> UserAsync(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, role);
        return api.CreateClient((await api.LoginAsync(username, Password)).AccessToken);
    }

    /// <summary>دور اختبار بصلاحيات محددة (قاعدة الاختبار فقط).</summary>
    private async Task<HttpClient> WithPermissionsAsync(IEnumerable<string> permissions)
    {
        var code = $"t_{Guid.NewGuid():N}"[..16];
        await api.WithDbAsync(async db =>
        {
            var role = new Role { Code = code, NameAr = code };
            role.Permissions.AddRange(permissions.Select(p => new RolePermission { Permission = p }));
            db.Roles.Add(role);
            await db.SaveChangesAsync();
        });
        return await UserAsync(code);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response)
    {
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private static async Task<(string? Code, string? Data)> Problem(HttpResponseMessage response)
    {
        var root = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        return (root.GetProperty("code").GetString(),
            root.TryGetProperty("data", out var d) && d.ValueKind == JsonValueKind.String ? d.GetString() : null);
    }

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    /// <summary>صف ناقص (بلا رقم) يُحفظ «بانتظار الاستكمال».</summary>
    private static async Task<Guid> PendingAsync(HttpClient client, string audience = QuickEntryAudience.Customers,
        string? phone = null)
    {
        var row = new QuickEntryRow(Guid.CreateVersion7(), 1, null, "صف تنظيف", phone, "PP", null);
        await Read<QuickBatchResult>(await Post(client, "/api/v1/quick-entry/batches",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, audience, [row])));
        return row.Id;
    }

    private Task<ImportEntry> EntryAsync(Guid id) =>
        api.WithDbAsync(db => db.ImportEntries.AsNoTracking().SingleAsync(e => e.Id == id));

    private Task<(int Parties, int Grades, int Materials, int Interests, int Products)> CountsAsync() =>
        api.WithDbAsync(async db => (await db.Parties.CountAsync(), await db.Grades.CountAsync(),
            await db.Materials.CountAsync(), await db.CustomerInterests.CountAsync(), await db.SupplierProducts.CountAsync()));

    private static JsonElement Cases(string name)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var path = Path.Combine(dir.FullName, "testdata", "quick_entry", "cleanup_cases.json");
            if (File.Exists(path))
                return JsonDocument.Parse(File.ReadAllText(path)).RootElement.GetProperty(name);
        }
        throw new FileNotFoundException("cleanup_cases.json");
    }

    [Fact]
    public async Task Shared_eligibility_cases_protect_cards_and_uncertain_promotions()
    {
        var owner = await UserAsync(SystemRoles.Representative);
        var failures = new List<string>();
        foreach (var c in Cases("eligibility").EnumerateArray())
        {
            var caseId = c.GetProperty("id").GetString();
            var status = c.GetProperty("status").GetString();
            var expected = c.GetProperty("expected").GetString();
            Guid id;
            if (status == ImportEntryStatus.Completed)
            {
                // صف جاهز يصبح بطاقة فعلًا.
                var row = new QuickEntryRow(Guid.CreateVersion7(), 1, null, "صف مكتمل", Mobile(), "PP", null);
                await Read<QuickBatchResult>(await Post(owner, "/api/v1/quick-entry/batches",
                    new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, QuickEntryAudience.Customers, [row])));
                id = row.Id;
            }
            else
            {
                id = await PendingAsync(owner);
                if (c.GetProperty("partyWithSameId").GetBoolean())
                    await Read<PartyDetail>(await Post(owner, "/api/v1/parties", new CreatePartyRequest(id, "بطاقة بنفس المعرف",
                        true, false, [new PhoneInput(Mobile())], Interests: ApiFactory.FixtureInterests)));
                var linked = c.GetProperty("partyId").GetBoolean();
                await api.WithDbAsync(async db =>
                {
                    var e = await db.ImportEntries.SingleAsync(x => x.Id == id);
                    e.Status = status!;
                    if (linked)
                        e.PartyId = await db.Parties.Select(p => p.Id).FirstAsync();
                    await db.SaveChangesAsync();
                });
            }
            var before = await CountsAsync();
            var response = await Post(owner, $"/api/v1/quick-entry/pending/{id}/discard", new { });
            var after = await EntryAsync(id);
            switch (expected)
            {
                case "eligible":
                    if (!response.IsSuccessStatusCode || after.Status != ImportEntryStatus.Discarded)
                        failures.Add($"{caseId}: expected discarded, got {(int)response.StatusCode} {after.Status}");
                    break;
                case "already_discarded":
                    var outcome = response.IsSuccessStatusCode ? await Read<DiscardOutcome>(response) : null;
                    if (outcome?.Outcome != "already_discarded")
                        failures.Add($"{caseId}: expected already_discarded, got {(int)response.StatusCode}");
                    break;
                case "protected":
                    var (code, data) = await Problem(response);
                    var reason = c.GetProperty("reason").GetString();
                    var ok = response.StatusCode == HttpStatusCode.Conflict && after.Status == status
                        && (reason == DiscardReasons.Completed ? code == "quick.closed" : code == "quick.protected" && data == reason);
                    if (!ok)
                        failures.Add($"{caseId}: expected protected {reason}, got {(int)response.StatusCode} {code} {data} {after.Status}");
                    break;
                case "not_listed":
                    // صفوف «بلا صلاحية» لا تظهر في القائمة ولا في العداد ولا في «حذف الكل».
                    var preview = await Read<DiscardAllResult>(await Post(owner, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
                    if (preview.ProtectedItems.Any(p => p.Id == id))
                        failures.Add($"{caseId}: failed row listed in clear-all");
                    break;
            }
            if (before != await CountsAsync())
                failures.Add($"{caseId}: cards or catalog changed");
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public async Task Shared_rbac_cases_allow_owners_and_record_managers_only()
    {
        var otherOwner = await UserAsync(SystemRoles.SystemAdmin);
        var failures = new List<string>();
        foreach (var c in Cases("rbac").EnumerateArray())
        {
            var caseId = c.GetProperty("id").GetString();
            var permissions = c.GetProperty("permissions").EnumerateArray().Select(p => p.GetString()!).ToList();
            var actor = await WithPermissionsAsync(permissions);
            var kind = c.GetProperty("kind").GetString()!;
            var id = c.GetProperty("owner").GetString() == "self"
                ? await PendingAsync(actor, kind)
                : await PendingAsync(otherOwner, kind);
            var response = await Post(actor, $"/api/v1/quick-entry/pending/{id}/discard", new { });
            var discarded = (await EntryAsync(id)).Status == ImportEntryStatus.Discarded;
            var allowed = c.GetProperty("expected").GetString() == "allowed";
            if (allowed != (response.IsSuccessStatusCode && discarded))
                failures.Add($"{caseId}: expected {(allowed ? "allowed" : "denied")}, got {(int)response.StatusCode} discarded={discarded}");
            if (!allowed && response.StatusCode is not (HttpStatusCode.Forbidden or HttpStatusCode.NotFound))
                failures.Add($"{caseId}: denial should be 403/404, got {(int)response.StatusCode}");

            // نفس القرار عبر الاستبعاد الجماعي (إن كان المستخدم يستخدم الإدخال السريع أصلًا).
            if (!allowed && permissions.Any(p => p.EndsWith(".create", StringComparison.Ordinal)))
            {
                var many = await Read<DiscardManyResult>(await Post(actor, "/api/v1/quick-entry/pending/discard", new { ids = new[] { id } }));
                if (many.Discarded != 0 || (await EntryAsync(id)).Status == ImportEntryStatus.Discarded)
                    failures.Add($"{caseId}: bulk discard bypassed the permission check");
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public async Task Bulk_discard_is_atomic_idempotent_and_skips_protected_rows()
    {
        var rep = await UserAsync(SystemRoles.Representative);
        var other = await UserAsync(SystemRoles.Representative);
        var a = await PendingAsync(rep);
        var b = await PendingAsync(rep);
        var protectedId = await PendingAsync(rep);
        await api.WithDbAsync(async db =>
        {
            (await db.ImportEntries.SingleAsync(e => e.Id == protectedId)).AwaitingPromotion = true;
            await db.SaveChangesAsync();
        });
        var foreign = await PendingAsync(other);
        var before = await CountsAsync();
        var auditBefore = await api.WithDbAsync(db => db.AuditEntries.CountAsync());

        var result = await Read<DiscardManyResult>(await Post(rep, "/api/v1/quick-entry/pending/discard",
            new { ids = new[] { a, b, protectedId, foreign, Guid.NewGuid() } }));
        Assert.Equal(2, result.Discarded);
        Assert.Equal(0, result.AlreadyDiscarded);
        Assert.Contains(result.Skipped, s => s.Id == protectedId && s.Reason == DiscardReasons.AwaitingPromotion);
        // صف مستخدم آخر لا يُكشف وجوده.
        Assert.Contains(result.Skipped, s => s.Id == foreign && s.Reason == DiscardReasons.NotFound);
        Assert.Equal(1, result.RemainingPending);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(foreign)).Status);

        // تكرار الطلب آمن.
        var again = await Read<DiscardManyResult>(await Post(rep, "/api/v1/quick-entry/pending/discard", new { ids = new[] { a, b } }));
        Assert.Equal(0, again.Discarded);
        Assert.Equal(2, again.AlreadyDiscarded);

        // عدادات الدفعة، والتدقيق إضافة فقط، والبطاقات والكتالوج كما هي.
        var batch = await api.WithDbAsync(async db =>
        {
            var batchId = (await db.ImportEntries.SingleAsync(e => e.Id == a)).BatchId;
            return await db.ImportBatches.SingleAsync(x => x.Id == batchId);
        });
        Assert.Equal(0, batch.PendingCount);
        Assert.True(await api.WithDbAsync(db => db.AuditEntries.AnyAsync(x => x.Action == "quick.discard_bulk")));
        Assert.True(await api.WithDbAsync(db => db.AuditEntries.CountAsync()) > auditBefore);
        Assert.Equal(before, await CountsAsync());

        Assert.Equal(HttpStatusCode.BadRequest,
            (await Post(rep, "/api/v1/quick-entry/pending/discard", new { ids = Array.Empty<Guid>() })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Post(rep, "/api/v1/quick-entry/pending/discard",
            new { ids = Enumerable.Range(0, QuickEntryService.MaxDiscardIds + 1).Select(_ => Guid.NewGuid()) })).StatusCode);
    }

    [Fact]
    public async Task Clear_all_needs_a_fresh_preview_and_leaves_only_protected_rows()
    {
        var rep = await UserAsync(SystemRoles.Representative);
        var e1 = await PendingAsync(rep);
        await PendingAsync(rep);
        // مكرر: نفس رقم بطاقة موجودة.
        var phone = Mobile();
        await Read<QuickBatchResult>(await Post(rep, "/api/v1/quick-entry/batches", new QuickBatchRequest(Guid.CreateVersion7(),
            QuickEntryMethods.Paste, QuickEntryAudience.Customers,
            [new QuickEntryRow(Guid.CreateVersion7(), 1, null, "أصل", phone, "PP", null)])));
        await PendingAsync(rep, phone: phone);
        // إنشاء غير مؤكد: بطاقة بنفس معرف صف معلق.
        var uncertain = await PendingAsync(rep);
        await Read<PartyDetail>(await Post(rep, "/api/v1/parties", new CreatePartyRequest(uncertain, "بطاقة معلقة",
            true, false, [new PhoneInput(Mobile())], Interests: ApiFactory.FixtureInterests)));
        var before = await CountsAsync();

        Assert.Equal("quick.preview_required",
            (await Problem(await Post(rep, "/api/v1/quick-entry/pending/discard-all", new { preview = false }))).Code);

        var preview = await Read<DiscardAllResult>(await Post(rep, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        Assert.False(preview.Committed);
        Assert.Equal(3, preview.Eligible);
        Assert.Equal(1, preview.Protected);
        Assert.Equal(1, preview.ProtectedByReason[DiscardReasons.UncertainPromotion]);
        Assert.Equal(1, preview.RemainingPending);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(e1)).Status); // المعاينة لا تكتب شيئًا

        // صف جديد بعد المعاينة: الرمز القديم مرفوض ولا يُستبعد شيء.
        var late = await PendingAsync(rep);
        var stale = await Post(rep, "/api/v1/quick-entry/pending/discard-all", new { preview = false, token = preview.Token });
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("quick.snapshot_changed", (await Problem(stale)).Code);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(e1)).Status);

        var fresh = await Read<DiscardAllResult>(await Post(rep, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        Assert.Equal(4, fresh.Eligible);
        var done = await Read<DiscardAllResult>(await Post(rep, "/api/v1/quick-entry/pending/discard-all",
            new { preview = false, token = fresh.Token }));
        Assert.True(done.Committed);
        Assert.Equal(4, done.Eligible);
        Assert.Equal(1, done.RemainingPending); // العداد = المحمي فقط
        Assert.Equal(ImportEntryStatus.Discarded, (await EntryAsync(late)).Status);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(uncertain)).Status);
        var pending = await Read<PagedResult<PendingEntryDto>>(await rep.GetAsync("/api/v1/quick-entry/pending?take=200"));
        Assert.Equal(1, pending.Total);

        // البطاقات والكتالوج كما هي، وسجل الدفعات باقٍ (الاستبعاد منطقي).
        Assert.Equal(before.Parties, (await CountsAsync()).Parties);
        Assert.Equal(before, await CountsAsync());
        Assert.True(await api.WithDbAsync(db => db.ImportEntries.AnyAsync(e => e.Id == e1)));
        Assert.True(await api.WithDbAsync(db => db.AuditEntries.AnyAsync(x => x.Action == "quick.discard_all")));

        // لا شيء مؤهل: التنفيذ بلا أثر.
        var empty = await Read<DiscardAllResult>(await Post(rep, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        Assert.Equal(0, empty.Eligible);
        var none = await Read<DiscardAllResult>(await Post(rep, "/api/v1/quick-entry/pending/discard-all",
            new { preview = false, token = empty.Token }));
        Assert.Equal(0, none.Eligible);
    }

    [Fact]
    public async Task Clear_all_respects_supplier_visibility_and_record_ownership()
    {
        var admin = await UserAsync(SystemRoles.SystemAdmin);
        var supplierRow = await PendingAsync(admin, QuickEntryAudience.Suppliers);
        var customerRow = await PendingAsync(admin);
        // يرى كل العملاء ويدير السجلات لكنه لا يرى الموردين.
        var manager = await WithPermissionsAsync([Permissions.CustomersCreate, Permissions.CustomersView,
            Permissions.CustomersViewAll, Permissions.RecordsManage]);
        var preview = await Read<DiscardAllResult>(await Post(manager, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        await Read<DiscardAllResult>(await Post(manager, "/api/v1/quick-entry/pending/discard-all",
            new { preview = false, token = preview.Token }));
        Assert.Equal(ImportEntryStatus.Discarded, (await EntryAsync(customerRow)).Status);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(supplierRow)).Status);

        // يرى كل العملاء دون إدارة السجلات: صفوف غيره محمية في المعاينة.
        var other = await PendingAsync(admin);
        var viewer = await WithPermissionsAsync([Permissions.CustomersCreate, Permissions.CustomersView, Permissions.CustomersViewAll]);
        var seen = await Read<DiscardAllResult>(await Post(viewer, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        Assert.Contains(seen.ProtectedItems, p => p.Id == other && p.Reason == DiscardReasons.Forbidden);
        await Read<DiscardAllResult>(await Post(viewer, "/api/v1/quick-entry/pending/discard-all",
            new { preview = false, token = seen.Token }));
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(other)).Status);

        // بلا صلاحية إدخال سريع أصلًا.
        var none = await WithPermissionsAsync([Permissions.CustomersView]);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await Post(none, "/api/v1/quick-entry/pending/discard-all", new { preview = true })).StatusCode);
    }
}
