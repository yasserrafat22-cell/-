using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Qadisiyah.Application.Crm;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>
/// تزامن «الإنشاء» و«الاستبعاد» لنفس صف «بانتظار الاستكمال». نقطة مراقبة توقف إحدى العمليتين عند نقطة
/// محددة (بعد حجز الصف للإنشاء، أو بعد قفل صفوف الاستبعاد) وتُشغَّل الأخرى، وانتظار القفل يُكتشف من
/// PostgreSQL نفسه (pg_stat_activity) لا بالتوقيت. النتيجة المطلوبة دائمًا: إما بطاقة واحدة وصف مكتمل، أو
/// صف مستبعد بلا بطاقة — لا الاثنان أبدًا.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class QuickEntryConcurrencyTests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    /// <summary>يوقف العملية عند النقطة المطلوبة حتى يسمح الاختبار بالمتابعة.</summary>
    private sealed class GateProbe : IQuickEntryProbe
    {
        public Guid? PauseClaim;
        public Guid? PauseDiscard;
        public readonly TaskCompletionSource ClaimReached = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource ClaimRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource DiscardReached = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource DiscardRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task AfterPromotionClaimAsync(Guid entryId, CancellationToken ct)
        {
            if (entryId != PauseClaim)
                return;
            ClaimReached.TrySetResult();
            await ClaimRelease.Task.WaitAsync(Timeout, ct);
        }

        public async Task BeforeDiscardMutationAsync(IReadOnlyCollection<Guid> entryIds, CancellationToken ct)
        {
            if (PauseDiscard is not { } id || !entryIds.Contains(id))
                return;
            DiscardReached.TrySetResult();
            await DiscardRelease.Task.WaitAsync(Timeout, ct);
        }
    }

    private sealed record Env(GateProbe Probe, HttpClient Rep, HttpClient Admin, Guid RepId);

    private async Task<Env> EnvAsync()
    {
        var probe = new GateProbe();
        var factory = api.WithWebHostBuilder(b => b.ConfigureTestServices(s =>
        {
            s.RemoveAll<IQuickEntryProbe>();
            s.AddSingleton<IQuickEntryProbe>(probe);
        }));
        async Task<(HttpClient, Guid)> Client(string role)
        {
            var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
            var id = await api.CreateUserAsync(username, Password, role);
            var token = (await api.LoginAsync(username, Password)).AccessToken;
            var client = factory.CreateClient();
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            return (client, id);
        }
        var (rep, repId) = await Client(SystemRoles.Representative);
        var (admin, _) = await Client(SystemRoles.SystemAdmin);
        return new Env(probe, rep, admin, repId);
    }

    private static string Mobile() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

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

    /// <summary>صف معلق ثم مُكمَل البيانات (جاهز للإنشاء يدويًا) دون أن يصبح بطاقة.</summary>
    private static async Task<Guid> CompletableAsync(HttpClient client, string audience = QuickEntryAudience.Customers)
    {
        // اسم فريد حتى لا يتدخل كشف الأسماء المشابهة بين الاختبارات.
        var name = $"صف تزامن {Guid.NewGuid():N}";
        var row = new QuickEntryRow(Guid.CreateVersion7(), 1, null, name, null, "PP", null);
        await Read<QuickBatchResult>(await Post(client, "/api/v1/quick-entry/batches",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Paste, audience, [row])));
        await Read<PendingEntryDto>(await client.PutAsJsonAsync($"/api/v1/quick-entry/pending/{row.Id}",
            new PendingUpdate(audience, name, Mobile(), "PP", null), Json));
        return row.Id;
    }

    private Task<ImportEntry> EntryAsync(Guid id) =>
        api.WithDbAsync(db => db.ImportEntries.AsNoTracking().SingleAsync(e => e.Id == id));

    private Task<bool> PartyExistsAsync(Guid id) => api.WithDbAsync(db => db.Parties.AnyAsync(p => p.Id == id));

    private Task<int> AuditAsync(string action, Guid? entity = null) => api.WithDbAsync(db =>
        db.AuditEntries.CountAsync(a => a.Action == action && (entity == null || a.EntityId == entity)));

    /// <summary>ينتظر حتى تنتظر جلسة في قاعدة الاختبار قفلًا (الطلب المتزامن وصل لنقطة التعارض فعلًا).</summary>
    private async Task WaitForLockWaitAsync()
    {
        var deadline = DateTime.UtcNow + Timeout;
        while (DateTime.UtcNow < deadline)
        {
            var waiting = await api.WithDbAsync(db => db.Database.SqlQueryRaw<int>(
                "SELECT count(*)::int AS \"Value\" FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'")
                .SingleAsync());
            if (waiting > 0)
                return;
            await Task.Delay(50);
        }
        Assert.Fail("الطلب المتزامن لم يصل لانتظار القفل");
    }

    /// <summary>عدادات كل دفعة تساوي حالات صفوفها الفعلية.</summary>
    private async Task AssertBatchCountersAsync(params Guid[] entryIds)
    {
        await api.WithDbAsync(async db =>
        {
            var batchIds = await db.ImportEntries.Where(e => entryIds.Contains(e.Id)).Select(e => e.BatchId).Distinct().ToListAsync();
            foreach (var batch in await db.ImportBatches.AsNoTracking().Where(b => batchIds.Contains(b.Id)).ToListAsync())
            {
                var statuses = await db.ImportEntries.Where(e => e.BatchId == batch.Id).Select(e => e.Status).ToListAsync();
                Assert.Equal(statuses.Count(s => s == ImportEntryStatus.Completed), batch.CreatedCount);
                Assert.Equal(statuses.Count(s => s == ImportEntryStatus.Pending), batch.PendingCount);
                Assert.Equal(statuses.Count(s => s == ImportEntryStatus.Duplicate), batch.DuplicateCount);
                Assert.Equal(statuses.Count(s => s == ImportEntryStatus.Failed), batch.FailedCount);
            }
        });
    }

    [Fact]
    public async Task A_row_being_promoted_cannot_be_discarded_by_any_path()
    {
        var env = await EnvAsync();
        var id = await CompletableAsync(env.Rep);
        env.Probe.PauseClaim = id;
        var completing = Post(env.Rep, $"/api/v1/quick-entry/pending/{id}/complete", new { });
        await env.Probe.ClaimReached.Task.WaitAsync(Timeout);

        // الإنشاء متوقف بعد الحجز: كل طرق الاستبعاد ترفضه (دون انتظار، فالحجز معتمد).
        var single = await Post(env.Rep, $"/api/v1/quick-entry/pending/{id}/discard", new { });
        Assert.Equal(HttpStatusCode.Conflict, single.StatusCode);
        Assert.Equal(("quick.protected", DiscardReasons.AwaitingPromotion), await Problem(single));
        var bulk = await Read<DiscardManyResult>(await Post(env.Rep, "/api/v1/quick-entry/pending/discard", new { ids = new[] { id } }));
        Assert.Equal(0, bulk.Discarded);
        Assert.Contains(bulk.Skipped, s => s.Id == id && s.Reason == DiscardReasons.AwaitingPromotion);
        var preview = await Read<DiscardAllResult>(await Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        Assert.Contains(preview.ProtectedItems, p => p.Id == id && p.Reason == DiscardReasons.AwaitingPromotion);
        var all = await Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = false, token = preview.Token });
        Assert.True(all.IsSuccessStatusCode, await all.Content.ReadAsStringAsync());

        env.Probe.ClaimRelease.SetResult();
        var done = await Read<CompletedEntry>(await completing);
        Assert.Equal(id, done.PartyId);
        var entry = await EntryAsync(id);
        Assert.Equal(ImportEntryStatus.Completed, entry.Status);
        Assert.False(entry.AwaitingPromotion);
        Assert.True(await PartyExistsAsync(id));
        Assert.Equal(0, await AuditAsync("quick.discarded", id));
        Assert.Equal(1, await AuditAsync("party.created", id));
        await AssertBatchCountersAsync(id);
    }

    [Theory]
    [InlineData("single")]
    [InlineData("bulk")]
    [InlineData("all")]
    public async Task A_discard_holding_its_locks_makes_a_concurrent_promotion_fail_cleanly(string path)
    {
        var env = await EnvAsync();
        var id = await CompletableAsync(env.Rep);
        var token = path == "all"
            ? (await Read<DiscardAllResult>(await Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = true }))).Token
            : null;
        env.Probe.PauseDiscard = id;
        var discarding = path switch
        {
            "single" => Post(env.Rep, $"/api/v1/quick-entry/pending/{id}/discard", new { }),
            "bulk" => Post(env.Rep, "/api/v1/quick-entry/pending/discard", new { ids = new[] { id } }),
            _ => Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = false, token }),
        };
        await env.Probe.DiscardReached.Task.WaitAsync(Timeout);

        // الاستبعاد متوقف وقفل الصف معه: الإنشاء المتزامن ينتظر القفل فعلًا.
        var completing = Post(env.Rep, $"/api/v1/quick-entry/pending/{id}/complete", new { });
        await WaitForLockWaitAsync();
        env.Probe.DiscardRelease.SetResult();

        Assert.True((await discarding).IsSuccessStatusCode, await (await discarding).Content.ReadAsStringAsync());
        var promotion = await completing;
        Assert.Equal(HttpStatusCode.Conflict, promotion.StatusCode);
        Assert.Equal("quick.closed", (await Problem(promotion)).Code);
        Assert.Equal(ImportEntryStatus.Discarded, (await EntryAsync(id)).Status);
        Assert.False(await PartyExistsAsync(id));
        Assert.Equal(0, await AuditAsync("party.created", id));
        await AssertBatchCountersAsync(id);
    }

    [Fact]
    public async Task Edits_and_insertions_during_a_discard_all_never_make_cleanup_unsafe()
    {
        var env = await EnvAsync();
        var edited = await CompletableAsync(env.Rep);
        var other = await CompletableAsync(env.Rep);
        var preview = await Read<DiscardAllResult>(await Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = true }));
        Assert.Equal(2, preview.Eligible);
        env.Probe.PauseDiscard = edited;
        var discarding = Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = false, token = preview.Token });
        await env.Probe.DiscardReached.Task.WaitAsync(Timeout);

        // تعديل صف مقفول ينتظر حتى ينتهي الاستبعاد ثم يُرفض؛ والصف الجديد لا يُستبعد لأنه لم يكن في المعاينة.
        var editing = env.Rep.PutAsJsonAsync($"/api/v1/quick-entry/pending/{edited}",
            new PendingUpdate(QuickEntryAudience.Customers, "اسم بعد المعاينة", Mobile(), "PP", null), Json);
        await WaitForLockWaitAsync();
        var inserted = await CompletableAsync(env.Rep);
        env.Probe.DiscardRelease.SetResult();

        var result = await Read<DiscardAllResult>(await discarding);
        Assert.Equal(2, result.Eligible);
        var edit = await editing;
        Assert.Equal(HttpStatusCode.Conflict, edit.StatusCode);
        Assert.Equal("quick.closed", (await Problem(edit)).Code);
        var e = await EntryAsync(edited);
        Assert.Equal(ImportEntryStatus.Discarded, e.Status);
        Assert.StartsWith("صف تزامن", e.Name); // التعديل المتأخر لم يُكتب
        Assert.Equal(ImportEntryStatus.Discarded, (await EntryAsync(other)).Status);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(inserted)).Status);
        Assert.Equal(1, result.RemainingPending);

        // ومعاينة قديمة بعد أي تغيير تُرفض دون أي استبعاد.
        var stale = await Post(env.Rep, "/api/v1/quick-entry/pending/discard-all", new { preview = false, token = preview.Token });
        Assert.Equal("quick.snapshot_changed", (await Problem(stale)).Code);
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(inserted)).Status);
        await AssertBatchCountersAsync(edited, other, inserted);
    }

    [Fact]
    public async Task Racing_promotions_and_discards_never_produce_both_outcomes()
    {
        var env = await EnvAsync();
        var supplierRow = await CompletableAsync(env.Admin, QuickEntryAudience.Suppliers);
        var ids = new List<Guid>();
        for (var i = 0; i < 8; i++)
            ids.Add(await CompletableAsync(env.Rep));
        var auditBefore = await api.WithDbAsync(db => db.AuditEntries.CountAsync());

        // سباق حقيقي بلا توقف: إنشاء مكرر واستبعاد مكرر (فردي وجماعي) لكل صف في نفس اللحظة.
        var requests = new List<Task<HttpResponseMessage>>();
        foreach (var id in ids)
        {
            for (var k = 0; k < 3; k++)
            {
                requests.Add(Post(env.Rep, $"/api/v1/quick-entry/pending/{id}/complete", new { }));
                requests.Add(Post(env.Rep, $"/api/v1/quick-entry/pending/{id}/discard", new { }));
            }
        }
        requests.Add(Post(env.Rep, "/api/v1/quick-entry/pending/discard", new { ids = ids.Append(supplierRow).ToArray() }));
        var responses = await Task.WhenAll(requests);
        var errors = new List<string>();
        foreach (var r in responses.Where(r => (int)r.StatusCode >= 500))
            errors.Add($"{r.RequestMessage?.RequestUri?.AbsolutePath}: {await r.Content.ReadAsStringAsync()}");
        Assert.True(errors.Count == 0, string.Join(Environment.NewLine, errors));

        foreach (var id in ids)
        {
            var entry = await EntryAsync(id);
            var party = await PartyExistsAsync(id);
            Assert.False(entry.AwaitingPromotion);
            if (entry.Status == ImportEntryStatus.Completed)
            {
                Assert.True(party);
                Assert.Equal(0, await AuditAsync("quick.discarded", id));
                Assert.Equal(1, await AuditAsync("party.created", id));
            }
            else
            {
                // مستبعد، أو بقي معلقًا (كل محاولاته رُفضت بتعارض قابل للإعادة) — وفي الحالتين بلا بطاقة.
                Assert.Contains(entry.Status, new[] { ImportEntryStatus.Discarded, ImportEntryStatus.Pending });
                Assert.False(party);
                Assert.Equal(0, await AuditAsync("party.created", id));
            }
        }
        // صف المورد لمستخدم آخر لم يُكشف ولم يُلمس، والتدقيق إضافة فقط، والعدادات مطابقة.
        Assert.Equal(ImportEntryStatus.Pending, (await EntryAsync(supplierRow)).Status);
        Assert.True(await api.WithDbAsync(db => db.AuditEntries.CountAsync()) > auditBefore);
        await AssertBatchCountersAsync([.. ids, supplierRow]);
    }
}
