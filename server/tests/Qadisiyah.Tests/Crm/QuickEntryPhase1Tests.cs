using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>
/// الإدخال السريع 0.7.0 — المرحلة 1: الـ Grade الاختياري، حفظ الـ Grade غير الموثق دون لمس الكتالوج،
/// المراجعة الصريحة للملتبس، الاستكمال الآمن بعد الانقطاع، التشخيص، والتوافق مع نسخة 0.6.0.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class QuickEntryPhase1Tests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static string Mobile() => "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);

    /// <summary>لاحقة حروف فقط تعزل أكواد هذا الاختبار عن غيره (نفس القاعدة بعد التطبيع).</summary>
    private static string Suffix() => "Q" + new string(Enumerable.Range(0, 5).Select(_ => (char)('A' + Random.Shared.Next(26))).ToArray());

    private async Task<(HttpClient Client, Guid UserId)> ClientAs(string role)
    {
        var username = $"{role[..3]}_{Guid.NewGuid():N}"[..20];
        var id = await api.CreateUserAsync(username, Password, role);
        return (api.CreateClient((await api.LoginAsync(username, Password)).AccessToken), id);
    }

    private static async Task<T> Read<T>(HttpResponseMessage response)
    {
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private static async Task<string?> Code(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.GetProperty("code").GetString();

    private static Task<HttpResponseMessage> Post(HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json);

    private static QuickBatchRequest Batch(string audience, params QuickEntryRow[] rows) =>
        new(Guid.CreateVersion7(), QuickEntryMethods.Paste, audience, rows);

    private static QuickEntryRow Row(string? name, string? phone, string? material, string? grade, string? maker = null,
        string? origin = null, bool ack = false, Guid? id = null) =>
        new(id ?? Guid.CreateVersion7(), 1, null, name, phone, material, grade, maker, Origin: origin, ReviewAcknowledged: ack);

    private static string Fixture(string name)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var path = Path.Combine(dir.FullName, "testdata", "quick_entry", name);
            if (File.Exists(path))
                return File.ReadAllText(path);
        }
        throw new FileNotFoundException(name);
    }

    private Task<int> GradeCountAsync(string code) => api.WithDbAsync(db =>
        db.Grades.CountAsync(g => g.NormalizedCode == TextNormalizer.NormalizeCode(code)));

    private async Task<Guid> MaterialIdAsync(string code) =>
        await api.WithDbAsync(db => db.Materials.Where(m => m.Code == code).Select(m => m.Id).SingleAsync());

    /// <summary>كتالوج <c>testdata/quick_entry/catalog.json</c> على قاعدة الاختبار بأكواد معزولة.</summary>
    private async Task<(Dictionary<string, Guid> Ids, Dictionary<string, string> Makers, string Suffix)> SeedFixtureCatalogAsync(
        HttpClient admin)
    {
        var suffix = Suffix();
        var catalog = JsonDocument.Parse(Fixture("catalog.json")).RootElement;
        var makerIds = new Dictionary<string, Guid>();
        var makerNames = new Dictionary<string, string>();
        foreach (var m in catalog.GetProperty("manufacturers").EnumerateArray())
        {
            var fixtureName = m.GetProperty("name").GetString()!;
            // «سابك» باسمه الحقيقي ليطابق مرادفه SABIC؛ غيره باسم فريد.
            var name = fixtureName == "سابك" ? fixtureName : $"{fixtureName} {suffix}";
            var existing = await api.WithDbAsync(db => db.Manufacturers.Where(x => x.Name == name).Select(x => (Guid?)x.Id)
                .FirstOrDefaultAsync());
            makerIds[m.GetProperty("id").GetString()!] = existing ?? (await Read<ManufacturerDto>(
                await Post(admin, "/api/v1/catalog/manufacturers", new CreateManufacturerRequest(name)))).Id;
            makerNames[fixtureName] = name;
        }

        var ids = new Dictionary<string, Guid>();
        foreach (var m in catalog.GetProperty("materials").EnumerateArray())
        {
            var materialId = await MaterialIdAsync(m.GetProperty("code").GetString()!);
            ids[m.GetProperty("id").GetString()!] = materialId;
            foreach (var g in m.GetProperty("grades").EnumerateArray())
            {
                var maker = g.GetProperty("manufacturerId").GetString() is { } mk ? makerIds[mk] : (Guid?)null;
                var created = await Read<CatalogGradeDto>(await Post(admin, "/api/v1/catalog/grades",
                    new CreateGradeRequest(materialId, maker, g.GetProperty("code").GetString() + suffix, ConfirmSimilar: true)));
                ids[g.GetProperty("id").GetString()!] = created.Id;
            }
        }
        return (ids, makerNames, suffix);
    }

    [Fact]
    public async Task Shared_validation_cases_match_the_server()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var (ids, makers, suffix) = await SeedFixtureCatalogAsync(admin);
        // أكواد الـ Grade في الحالات بلاحقة الاختبار (668 يبقى غير موجود بعدها أيضًا).
        string? Grade(string? g) => g is null ? null : g + suffix;

        var failures = new List<string>();
        foreach (var c in JsonDocument.Parse(Fixture("validation_cases.json")).RootElement.GetProperty("cases").EnumerateArray())
        {
            var id = c.GetProperty("id").GetString();
            var row = c.GetProperty("row");
            string? F(string field) => row.TryGetProperty(field, out var v) ? v.GetString() : null;
            var maker = F("manufacturer") is { } mk ? makers.GetValueOrDefault(mk, mk) : null;
            var request = Batch(c.GetProperty("audience").GetString()!,
                new QuickEntryRow(Guid.CreateVersion7(), 1, F("kind"), F("name"), F("phone"), F("material"), Grade(F("grade")),
                    maker, Origin: F("origin")));
            var actual = (await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/validate", request))).Rows.Single();

            var e = c.GetProperty("expected");
            var status = e.GetProperty("status").GetString() switch
            {
                "incomplete" => ImportEntryStatus.Pending,
                var s => s,
            };
            static HashSet<string> Set(JsonElement a) => a.EnumerateArray().Select(x => x.GetString()!).ToHashSet();
            Guid? Id(string field) => e.GetProperty(field).GetString() is { } k ? ids[k] : null;
            void Check(string what, object? expected, object? got)
            {
                if (!Equals(expected, got))
                    failures.Add($"{id} {what}: expected {expected ?? "null"}, got {got ?? "null"}");
            }

            Check("status", status, actual.Status);
            Check("blocking", string.Join(",", Set(e.GetProperty("blocking")).Order()), string.Join(",", actual.Issues.Order()));
            Check("warnings", string.Join(",", Set(e.GetProperty("warnings")).Order()),
                string.Join(",", (actual.Warnings ?? []).Order()));
            Check("material", Id("materialId"), actual.MaterialId);
            Check("grade", Id("gradeId"), actual.GradeId);
            Check("unverified", Grade(e.GetProperty("unverifiedGrade").GetString()), actual.UnverifiedGrade);
            Check("needsReview", status == QuickRowStatus.NeedsReview, actual.NeedsReview);
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public async Task An_unverified_grade_is_kept_on_the_record_without_touching_the_catalog()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var code = "668" + Suffix();
        var customerRow = Row("مصنع غير موثق", Mobile(), "HDPE", code, maker: "شركة غير معروفة");
        var supplierRow = Row("مورد غير موثق", Mobile(), "HDPE", code);
        var gradesBefore = await api.WithDbAsync(db => db.Grades.CountAsync());

        var customers = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches",
            Batch(QuickEntryAudience.Customers, customerRow)));
        var suppliers = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches",
            Batch(QuickEntryAudience.Suppliers, supplierRow)));
        Assert.Equal(ImportEntryStatus.Completed, customers.Rows.Single().Status);
        Assert.Equal(ImportEntryStatus.Completed, suppliers.Rows.Single().Status);
        Assert.Contains(QuickEntryIssues.GradeUnverified, customers.Rows.Single().Warnings!);

        // الكتالوج لم يتغير: لا Grade بهذا الكود ولا أي Grade جديد.
        Assert.Equal(0, await GradeCountAsync(code));
        Assert.Equal(gradesBefore, await api.WithDbAsync(db => db.Grades.CountAsync()));

        // العرض: الخامة مرتبطة، الـ Grade نص غير موثق، ولا ربط Grade.
        var customer = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{customerRow.Id}"));
        var need = customer.Interests.Single();
        Assert.Equal(await MaterialIdAsync("HDPE"), need.MaterialId);
        Assert.Null(need.GradeId);
        Assert.Equal(code, need.UnverifiedGrade);
        Assert.Equal("شركة غير معروفة", need.UnverifiedManufacturer);
        var supplier = await Read<PartyDetail>(await admin.GetAsync($"/api/v1/parties/{supplierRow.Id}"));
        Assert.Equal(code, supplier.Products.Single().UnverifiedGrade);
        Assert.Null(supplier.Products.Single().GradeId);

        // التصدير: يظهر مميزًا، وفلتر Grade الكتالوج لا يطابقه.
        var hdpe = await MaterialIdAsync("HDPE");
        var export = await Read<ExportResult>(await Post(admin, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Mixed, hdpe)));
        var exported = export.Rows.Single(r => r.PartyId == customerRow.Id);
        Assert.Equal($"{code} (غير موثق)", exported.Grade);
        Assert.Equal("شركة غير معروفة (غير موثق)", exported.Manufacturer);
        Assert.Contains(export.Rows, r => r.PartyId == supplierRow.Id && r.Grade == $"{code} (غير موثق)");
        var anyGrade = await api.WithDbAsync(db => db.Grades.Where(g => g.MaterialId == hdpe).Select(g => g.Id).FirstAsync());
        var filtered = await Read<ExportResult>(await Post(admin, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Mixed, hdpe, anyGrade)));
        Assert.DoesNotContain(filtered.Rows, r => r.PartyId == customerRow.Id || r.PartyId == supplierRow.Id);

        // البحث بالنص: نتيجة مميزة غير مطابقة تامة.
        var search = await Read<SearchResult>(await admin.GetAsync($"/api/v1/search?q={code}"));
        var card = search.Customers.Single(x => x.PartyId == customerRow.Id);
        Assert.False(card.Exact);
        Assert.Contains(card.Reasons, r => r.Contains("غير موثق", StringComparison.Ordinal));
        Assert.Contains(search.Suppliers, x => x.PartyId == supplierRow.Id);
    }

    [Fact]
    public async Task Unverified_supplier_grades_stay_hidden_from_users_who_cannot_see_suppliers()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var code = "575" + Suffix();
        var supplierRow = Row("مورد سري", Mobile(), "PP", code);
        var customerRow = Row("عميل المندوب", Mobile(), "PP", code);
        await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", Batch(QuickEntryAudience.Suppliers, supplierRow)));
        await Read<QuickBatchResult>(await Post(rep, "/api/v1/quick-entry/batches", Batch(QuickEntryAudience.Customers, customerRow)));

        var search = await Read<SearchResult>(await rep.GetAsync($"/api/v1/search?q={code}"));
        Assert.Contains(search.Customers, c => c.PartyId == customerRow.Id);
        Assert.Empty(search.Suppliers);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(rep, "/api/v1/quick-entry/export",
            new ExportRequest(QuickEntryAudience.Suppliers))).StatusCode);
    }

    [Fact]
    public async Task Manual_registration_still_requires_a_catalog_grade()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var pp = await MaterialIdAsync("PP");
        var response = await Post(admin, "/api/v1/parties", new CreatePartyRequest(Guid.CreateVersion7(), "تسجيل يدوي",
            true, false, [new PhoneInput(Mobile())], Interests: [new InterestInput(pp)]));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("party.grade_required", await Code(response));
    }

    [Fact]
    public async Task An_ambiguous_grade_is_saved_only_after_explicit_review()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var (ids, _, suffix) = await SeedFixtureCatalogAsync(admin);
        var tr144 = "TR144" + suffix;

        // بدون تأكيد: يُحفظ «بانتظار الاستكمال» ولا تُنشأ بطاقة.
        var row = Row("شركة ملتبسة", Mobile(), "HDPE", tr144);
        var batch = await Read<QuickBatchResult>(await Post(rep, "/api/v1/quick-entry/batches",
            Batch(QuickEntryAudience.Customers, row)));
        var stored = batch.Rows.Single();
        Assert.Equal(ImportEntryStatus.Pending, stored.Status);
        Assert.True(stored.NeedsReview);
        Assert.Empty(stored.Issues);
        Assert.Equal(1, batch.Pending);
        Assert.Equal(HttpStatusCode.NotFound, (await rep.GetAsync($"/api/v1/parties/{row.Id}")).StatusCode);

        var pending = await Read<PagedResult<PendingEntryDto>>(await rep.GetAsync("/api/v1/quick-entry/pending?take=200"));
        Assert.True(pending.Items.Single(p => p.Id == row.Id).NeedsReview);

        // الإكمال بدون تأكيد مرفوض، ومستخدم آخر لا يصل للصف.
        var refused = await Post(rep, $"/api/v1/quick-entry/pending/{row.Id}/complete", new { });
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("quick.review_required", await Code(refused));
        var (other, _) = await ClientAs(SystemRoles.Representative);
        Assert.Equal(HttpStatusCode.NotFound,
            (await Post(other, $"/api/v1/quick-entry/pending/{row.Id}/complete", new { acknowledgeReview = true })).StatusCode);

        // بالتأكيد: بطاقة بالخامة ونص الـ Grade غير موثق، دون أي ربط بأي من الشركتين.
        var done = await Read<CompletedEntry>(await Post(rep, $"/api/v1/quick-entry/pending/{row.Id}/complete",
            new { acknowledgeReview = true }));
        var party = await Read<PartyDetail>(await rep.GetAsync($"/api/v1/parties/{done.PartyId}"));
        Assert.Null(party.Interests.Single().GradeId);
        Assert.Equal(tr144, party.Interests.Single().UnverifiedGrade);
        Assert.NotEqual(ids["g-hdpe-tr144-a"], party.Interests.Single().GradeId);
        Assert.True(await api.WithDbAsync(db => db.AuditEntries.AnyAsync(a => a.Action == "quick.review_acknowledged" && a.EntityId == row.Id)));

        // التأكيد ضمن الدفعة نفسها ينشئ البطاقة مباشرة.
        var acked = Row("شركة ملتبسة مؤكدة", Mobile(), "HDPE", tr144, ack: true);
        var direct = await Read<QuickBatchResult>(await Post(rep, "/api/v1/quick-entry/batches",
            Batch(QuickEntryAudience.Customers, acked)));
        Assert.Equal(ImportEntryStatus.Completed, direct.Rows.Single().Status);

        // الشركة المصنعة لا تُستنتج: الكتالوج لم يتغير (شركتان فقط بهذا الكود).
        Assert.Equal(2, await GradeCountAsync(tr144));
    }

    [Fact]
    public async Task An_interrupted_batch_is_completed_on_retry_without_duplicates()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var phoneA = Mobile();
        var phoneB = Mobile();
        var a = Row("شركة انقطاع أ", null, "PP", null);
        var b = Row("شركة انقطاع ب", phoneB, "PP", null);
        var c = Row("شركة انقطاع ج", null, "PP", null);
        var request = Batch(QuickEntryAudience.Customers, a, b, c);
        var first = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", request));
        Assert.Equal(1, first.Created);

        // محاكاة الانقطاع:
        // (أ) صف حُفظ جاهزًا ثم انقطع الطلب قبل إنشاء بطاقته.
        // (ب) بطاقة أُنشئت ثم انقطع الطلب قبل تحديث الصف.
        // (ج) صف كان جاهزًا لكنه أصبح ناقصًا قبل الاستكمال.
        await api.WithDbAsync(async db =>
        {
            var ea = await db.ImportEntries.SingleAsync(e => e.Id == a.Id);
            ea.Phone = phoneA;
            ea.AwaitingPromotion = true;
            var eb = await db.ImportEntries.SingleAsync(e => e.Id == b.Id);
            eb.Status = ImportEntryStatus.Pending;
            eb.PartyId = null;
            eb.CreatedParty = false;
            eb.AwaitingPromotion = true;
            var ec = await db.ImportEntries.SingleAsync(e => e.Id == c.Id);
            ec.AwaitingPromotion = true;
            await db.SaveChangesAsync();
        });

        var retry = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", request));
        Assert.Equal(ImportEntryStatus.Completed, retry.Rows.Single(r => r.Id == a.Id).Status);
        Assert.Equal(ImportEntryStatus.Completed, retry.Rows.Single(r => r.Id == b.Id).Status);
        Assert.Equal(ImportEntryStatus.Pending, retry.Rows.Single(r => r.Id == c.Id).Status);
        Assert.Equal(2, retry.Created);

        var again = await Read<QuickBatchResult>(await Post(admin, "/api/v1/quick-entry/batches", request));
        Assert.Equal(retry.Rows.Select(r => (r.Id, r.Status)), again.Rows.Select(r => (r.Id, r.Status)));

        await api.WithDbAsync(async db =>
        {
            foreach (var phone in new[] { phoneA, phoneB })
            {
                var e164 = "+20" + phone[1..];
                Assert.Equal(1, await db.PartyPhones.CountAsync(p => p.E164 == e164));
            }
            var entries = await db.ImportEntries.Where(e => e.BatchId == request.Id).ToListAsync();
            Assert.All(entries, e => Assert.False(e.AwaitingPromotion));
            Assert.Equal(b.Id, entries.Single(e => e.Id == b.Id).PartyId);
            Assert.True(entries.Single(e => e.Id == b.Id).CreatedParty);
            var batch = await db.ImportBatches.SingleAsync(x => x.Id == request.Id);
            Assert.Equal(2, batch.CreatedCount);
            Assert.Equal(1, batch.PendingCount);
        });
    }

    [Fact]
    public async Task An_unexpected_processing_error_is_reported_apart_from_missing_data()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        var (rep, _) = await ClientAs(SystemRoles.Representative);
        var pp = await MaterialIdAsync("PP");
        // معرف مستخدم بالفعل لسجل أنشأه مستخدم آخر: خطأ معالجة وليس نقص بيانات.
        var taken = Guid.CreateVersion7();
        await Read<PartyDetail>(await Post(admin, "/api/v1/parties", new CreatePartyRequest(taken, "سجل قائم للمعرف",
            true, false, [new PhoneInput(Mobile())], Interests: ApiFactory.FixtureInterests)));

        var row = Row("صف بمعرف مأخوذ", Mobile(), "PP", null, id: taken);
        var result = await Read<QuickBatchResult>(await Post(rep, "/api/v1/quick-entry/batches",
            Batch(QuickEntryAudience.Customers, row)));
        var r = result.Rows.Single();
        Assert.Equal(ImportEntryStatus.Pending, r.Status);
        Assert.Empty(r.Issues);
        Assert.Equal("party.id_taken", r.ErrorCode);

        var pending = await Read<PagedResult<PendingEntryDto>>(await rep.GetAsync("/api/v1/quick-entry/pending?take=200"));
        Assert.Equal("party.id_taken", pending.Items.Single(p => p.Id == taken).ErrorCode);
        Assert.Equal(pp, pending.Items.Single(p => p.Id == taken).MaterialId);
    }

    [Fact]
    public async Task Requests_from_app_version_0_6_0_keep_working()
    {
        var (admin, _) = await ClientAs(SystemRoles.SystemAdmin);
        // نفس صيغة 0.6.0: بلا origin ولا reviewAcknowledged.
        var id = Guid.CreateVersion7();
        var batchId = Guid.CreateVersion7();
        var old = new
        {
            id = batchId, method = "paste", audience = "customer",
            rows = new[] { new { id, row = 1, kind = (string?)null, name = "عميل نسخة قديمة", phone = Mobile(), material = "PP", grade = (string?)null, manufacturer = (string?)null, materialId = (Guid?)null, gradeId = (Guid?)null } },
        };
        var preview = await admin.PostAsJsonAsync("/api/v1/quick-entry/validate", old);
        var json = JsonDocument.Parse(await preview.Content.ReadAsStringAsync()).RootElement;
        Assert.True(preview.IsSuccessStatusCode);
        var row = json.GetProperty("rows")[0];
        Assert.Equal("ready", row.GetProperty("status").GetString());
        Assert.Equal(0, row.GetProperty("issues").GetArrayLength());
        foreach (var field in new[] { "id", "row", "kind", "materialId", "gradeId", "materialCode", "gradeLabel", "partyId", "duplicateOfId", "duplicateName", "note" })
            Assert.True(row.TryGetProperty(field, out _), field);

        var committed = await admin.PostAsJsonAsync("/api/v1/quick-entry/batches", old);
        Assert.True(committed.IsSuccessStatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/v1/parties/{id}")).StatusCode);

        // إكمال وتحديث «بانتظار الاستكمال» بالصيغة القديمة (المنشأ المحفوظ من نسخة أحدث لا يُمسح).
        var pendingRow = Guid.CreateVersion7();
        await admin.PostAsJsonAsync("/api/v1/quick-entry/batches", new
        {
            id = Guid.CreateVersion7(), method = "paste", audience = "customer",
            rows = new[] { new { id = pendingRow, row = 1, name = "قديم ناقص", material = "PP", origin = "السعودية" } },
        });
        var update = await admin.PutAsJsonAsync($"/api/v1/quick-entry/pending/{pendingRow}", new
        {
            kind = "customer", name = "قديم ناقص", phone = Mobile(), material = "PP", grade = (string?)null,
        });
        Assert.True(update.IsSuccessStatusCode, await update.Content.ReadAsStringAsync());
        Assert.Equal("السعودية", await api.WithDbAsync(db => db.ImportEntries.Where(e => e.Id == pendingRow)
            .Select(e => e.OriginText).SingleAsync()));
        var complete = await admin.PostAsJsonAsync($"/api/v1/quick-entry/pending/{pendingRow}/complete", new { confirmSimilar = false });
        Assert.True(complete.IsSuccessStatusCode, await complete.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Rows_written_by_server_version_0_6_0_remain_valid_after_the_migration()
    {
        // نسخة السيرفر 0.6.0 (عند الرجوع إليها) تكتب الصفوف دون الأعمدة الجديدة: القيم الافتراضية تكفي.
        var (admin, userId) = await ClientAs(SystemRoles.SystemAdmin);
        var batchId = Guid.CreateVersion7();
        var entryId = Guid.CreateVersion7();
        var partyId = Guid.CreateVersion7();
        var pp = await MaterialIdAsync("PP");
        await api.WithDbAsync(async db =>
        {
            var now = DateTimeOffset.UtcNow;
            const string summary = "{}";
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                insert into import_batches (id, kind, file_sha256, summary, row_count, created_count, pending_count,
                    duplicate_count, failed_count, created_by, created_at, method, audience, status)
                values ({batchId}, 'quick', '', {summary}, 1, 0, 1, 0, 0, {userId}, {now}, 'paste', 'customer', 'processed')
                """);
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                insert into import_entries (id, batch_id, row_number, kind, name, phone, material_text, status,
                    created_party, created_by, created_at, updated_by, updated_at)
                values ({entryId}, {batchId}, 1, 'customer', 'صف من النسخة السابقة', {Mobile()}, 'PP', 'pending',
                    false, {userId}, {now}, {userId}, {now})
                """);
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                insert into parties (id, name, normalized_name, country_code, is_customer, is_supplier, name_missing,
                    created_by, created_at, updated_by, updated_at)
                values ({partyId}, 'عميل من النسخة السابقة', 'عميل من النسخه السابقه', 'EG', true, false, false,
                    {userId}, {now}, {userId}, {now})
                """);
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                insert into customer_interests (id, party_id, material_id, open_spec)
                values ({Guid.CreateVersion7()}, {partyId}, {pp}, false)
                """);
        });

        var entry = await api.WithDbAsync(db => db.ImportEntries.AsNoTracking().SingleAsync(e => e.Id == entryId));
        Assert.False(entry.AwaitingPromotion);
        Assert.False(entry.ReviewAcknowledged);
        Assert.Null(entry.OriginText);
        Assert.Null(entry.ErrorCode);
        var interest = await api.WithDbAsync(db => db.CustomerInterests.AsNoTracking().SingleAsync(i => i.PartyId == partyId));
        Assert.Null(interest.UnverifiedGrade);

        // ويُكمل بالنسخة الجديدة بشكل طبيعي.
        var done = await Read<CompletedEntry>(await Post(admin, $"/api/v1/quick-entry/pending/{entryId}/complete", new { }));
        Assert.Equal(entryId, done.PartyId);
    }
}
