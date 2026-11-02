using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Crm;

/// <summary>أسباب نقص الصف (يعرضها التطبيق بالعربية).</summary>
public static class QuickEntryIssues
{
    public const string NameMissing = "name_missing";
    public const string NameInvalid = "name_invalid";
    public const string PhoneMissing = "phone_missing";
    public const string PhoneInvalid = "phone_invalid";
    public const string MaterialMissing = "material_missing";
    public const string MaterialUnknown = "material_unknown";
    public const string GradeMissing = "grade_missing";
    public const string GradeUnknown = "grade_unknown";
    public const string GradeAmbiguous = "grade_ambiguous";
    public const string KindMissing = "kind_missing";
}

public static class QuickEntryMethods
{
    public const string Paste = "paste";
    public const string Excel = "excel";
}

public static class QuickEntryAudience
{
    public const string Customers = "customer";
    public const string Suppliers = "supplier";
    public const string Mixed = "mixed";
}

/// <summary>صف كما أدخله المستخدم (نص)، أو بمعرفات الكتالوج بعد الاختيار من القوائم.</summary>
public sealed record QuickEntryRow(Guid Id, int Row, string? Kind, string? Name, string? Phone, string? Material,
    string? Grade, string? Manufacturer = null, Guid? MaterialId = null, Guid? GradeId = null);

public sealed record QuickBatchRequest(Guid Id, string Method, string Audience, IReadOnlyList<QuickEntryRow> Rows,
    string? FileName = null);

/// <param name="Status">ready (معاينة) أو completed أو pending أو duplicate أو failed.</param>
public sealed record QuickRowResult(Guid Id, int Row, string Status, string? Kind, IReadOnlyList<string> Issues,
    Guid? MaterialId, Guid? GradeId, string? MaterialCode, string? GradeLabel, Guid? PartyId,
    Guid? DuplicateOfId, string? DuplicateName, string? Note);

public sealed record QuickBatchResult(Guid BatchId, bool Committed, int Total, int Created, int Pending, int Duplicate,
    int Failed, IReadOnlyList<QuickRowResult> Rows);

public sealed record PendingEntryDto(Guid Id, Guid BatchId, string? Method, int Row, string? Kind, string? Name,
    string? Phone, string? Material, string? Grade, string? Manufacturer, Guid? MaterialId, Guid? GradeId,
    string? MaterialCode, string? GradeLabel, string Status, IReadOnlyList<string> Issues, Guid? DuplicateOfId,
    string? DuplicateName, string? Note, Guid? PartyId, DateTimeOffset CreatedAt, string? CreatedByName);

public sealed record PendingUpdate(string? Kind, string? Name, string? Phone, string? Material, string? Grade,
    string? Manufacturer = null, Guid? MaterialId = null, Guid? GradeId = null);

public sealed record PendingQuery(string? Q = null, string? Kind = null, Guid? BatchId = null, string? Issue = null,
    string? Status = null, int Skip = 0, int Take = 50);

public sealed record CompleteEntryRequest(bool ConfirmSimilar = false);

public sealed record MergeEntryRequest(bool AddRole = false);

public sealed record CompletedEntry(Guid EntryId, Guid PartyId, bool Created);

public sealed record QuickBatchSummary(Guid Id, string? Method, string? Audience, string? FileName, int RowCount,
    int Created, int Pending, int Duplicate, int Failed, string? Status, DateTimeOffset CreatedAt, string? CreatedByName);

public sealed record UndoResult(int Reversed, int Discarded, IReadOnlyList<UndoBlocked> Blocked, string Status);

public sealed record UndoBlocked(Guid PartyId, string Name, string Reason);

public sealed record ExcelSheet(string Name, IReadOnlyList<string> Headers, IReadOnlyList<IReadOnlyList<string>> Rows,
    IReadOnlyDictionary<string, int> Mapping);

public sealed record ExportRequest(string Audience, Guid? MaterialId = null, Guid? GradeId = null);

/// <summary>صف تصدير: سجل واحد لكل ارتباط خامة/Grade (أو صف واحد بلا خامة عند تصدير الكل).</summary>
public sealed record ExportRow(string Kind, Guid PartyId, string Name, string? Phone, string? Material, string? Grade,
    string? Manufacturer);

public sealed record ExportResult(string Audience, int Customers, int Suppliers, IReadOnlyList<ExportRow> Rows);

/// <summary>
/// «الإدخال السريع»: لصق مباشر واستيراد Excel بمسار تحقق واحد، و«بانتظار الاستكمال»، والتصدير الذكي.
/// <list type="bullet">
/// <item>الصف يصبح بطاقة عميل/مورد فقط باسم، موبايل مصري صحيح، خامة، وGrade من الكتالوج الموحد — عبر
/// نفس خدمة التسجيل اليدوي (صلاحياتها وكشف تكرارها وتدقيقها)، وبمعرف الصف نفسه فلا تتكرر عند إعادة المحاولة.</item>
/// <item>الناقص يُحفظ منفصلًا ولا يمنع باقي الصفوف، ولا يظهر كعميل أو مورد أو في البحث والمطابقة.</item>
/// <item>لا تخمين: الخامة والـ Grade يُطابقان الكتالوج بالتطبيع فقط، والكود المسجل لأكثر من شركة يُترك للاختيار.</item>
/// </list>
/// </summary>
public sealed class QuickEntryService(
    IAppDbContext db,
    ICurrentUser user,
    PartyAccess access,
    PartyService parties,
    TimeProvider clock)
{
    public const int MaxRows = 5000;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static readonly IReadOnlyDictionary<string, string[]> Columns = new Dictionary<string, string[]>
    {
        ["name"] = ["الاسم", "اسم", "اسم الشركه", "الشركه", "اسم العميل", "اسم المورد", "العميل", "المورد", "name", "company", "company name"],
        ["phone"] = ["الهاتف", "هاتف", "رقم الهاتف", "التليفون", "تليفون", "الموبايل", "موبايل", "رقم الموبايل", "جوال", "phone", "mobile", "tel", "telephone"],
        ["material"] = ["الخامه", "خامه", "نوع الخامه", "material", "material type"],
        ["grade"] = ["grade", "الجريد", "جريد", "الدرجه", "grades"],
        ["manufacturer"] = ["الشركه المصنعه", "المصنع", "manufacturer", "maker", "producer"],
        ["kind"] = ["النوع", "نوع", "نوع السجل", "التصنيف", "عميل او مورد", "عميل/مورد", "type", "role"],
    };

    private bool CanCreateKind(string kind) => kind == QuickEntryAudience.Customers
        ? user.Has(Permissions.CustomersCreate)
        : user.Has(Permissions.SuppliersCreate);

    private bool CanUse => user.Has(Permissions.CustomersCreate) || user.Has(Permissions.SuppliersCreate);

    // ---------------- الكتالوج والتحقق ----------------

    private sealed class Catalog
    {
        public required List<Material> Materials;
        public required List<(Guid Id, Guid MaterialId, Guid? MakerId, string Code, string NormalizedCode, string? Maker)> Grades;
        public required Dictionary<Guid, string> MakerNames;
    }

    private async Task<Catalog> LoadCatalogAsync(CancellationToken ct)
    {
        var makers = await db.Manufacturers.AsNoTracking().ToDictionaryAsync(m => m.Id, m => m.Name, ct);
        var grades = (await db.Grades.AsNoTracking().Where(g => g.IsActive)
                .Select(g => new { g.Id, g.MaterialId, g.ManufacturerId, g.Code, g.NormalizedCode }).ToListAsync(ct))
            .Select(g => (g.Id, g.MaterialId, g.ManufacturerId, g.Code, g.NormalizedCode,
                g.ManufacturerId is { } m ? makers.GetValueOrDefault(m) : null))
            .ToList();
        return new Catalog
        {
            Materials = await db.Materials.AsNoTracking().Include(m => m.Aliases).Where(m => m.IsActive).ToListAsync(ct),
            Grades = grades,
            MakerNames = makers,
        };
    }

    private sealed record Resolved(string? Kind, string? Name, string? E164, Guid? MaterialId, Guid? GradeId,
        string? MaterialCode, string? GradeLabel, List<string> Issues);

    /// <summary>نوع السجل في الاستيراد المختلط بكلمات واضحة فقط؛ غيرها يبقى بلا نوع حتى يُصحح.</summary>
    public static string? ParseKind(string? value)
    {
        var t = TextNormalizer.Normalize(value);
        return t switch
        {
            "عميل" or "عملاء" or "العميل" or "العملاء" or "customer" or "customers" or "client" => QuickEntryAudience.Customers,
            "مورد" or "موردين" or "المورد" or "الموردون" or "الموردين" or "supplier" or "suppliers" or "vendor" =>
                QuickEntryAudience.Suppliers,
            _ => null,
        };
    }

    private static Resolved Resolve(QuickEntryRow row, string audience, Catalog catalog)
    {
        var issues = new List<string>();
        var kind = audience is QuickEntryAudience.Customers or QuickEntryAudience.Suppliers
            ? audience
            : row.Kind is QuickEntryAudience.Customers or QuickEntryAudience.Suppliers ? row.Kind : ParseKind(row.Kind);
        if (kind is null)
            issues.Add(QuickEntryIssues.KindMissing);

        var name = string.Join(' ', (row.Name ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (name.Length == 0)
            issues.Add(QuickEntryIssues.NameMissing);
        else if (name.Length is < 2 or > 200)
            issues.Add(QuickEntryIssues.NameInvalid);

        string? e164 = null;
        if (string.IsNullOrWhiteSpace(row.Phone))
            issues.Add(QuickEntryIssues.PhoneMissing);
        else
        {
            // موبايل مصري 11 رقمًا (010/011/012/015). صيغة +20 أو رقم بلا الصفر الأول (Excel يحذفه) تُوحد
            // لأنها غير ملتبسة؛ أي رقم آخر لا يُخمن.
            var normalized = PhoneNumber.Normalize(row.Phone);
            if (PhoneNumber.IsEgyptianMobile(normalized))
                e164 = normalized;
            else
                issues.Add(QuickEntryIssues.PhoneInvalid);
        }

        Material? material = null;
        var grade = default((Guid Id, Guid MaterialId, Guid? MakerId, string Code, string NormalizedCode, string? Maker)?);
        if (row.GradeId is { } gid)
        {
            var index = catalog.Grades.FindIndex(g => g.Id == gid);
            if (index >= 0)
                grade = catalog.Grades[index];
            else
                issues.Add(QuickEntryIssues.GradeUnknown);
        }
        if (row.MaterialId is { } mid)
            material = catalog.Materials.FirstOrDefault(m => m.Id == mid);
        else if (grade is { } chosen)
            material = catalog.Materials.FirstOrDefault(m => m.Id == chosen.MaterialId);
        else if (!string.IsNullOrWhiteSpace(row.Material))
        {
            var key = TextNormalizer.NormalizeCode(Synonyms.MaterialCode(TextNormalizer.Normalize(row.Material)) ?? row.Material);
            material = catalog.Materials.FirstOrDefault(m => TextNormalizer.NormalizeCode(m.Code) == key
                || m.Aliases.Any(a => a.Normalized == key));
        }
        if (material is null)
            issues.Add(row.MaterialId is null && string.IsNullOrWhiteSpace(row.Material) && grade is null
                ? QuickEntryIssues.MaterialMissing
                : QuickEntryIssues.MaterialUnknown);

        if (grade is { } picked && material is not null && picked.MaterialId != material.Id)
        {
            issues.Add(QuickEntryIssues.GradeUnknown);
            grade = null;
        }
        if (grade is null && row.GradeId is null)
        {
            if (string.IsNullOrWhiteSpace(row.Grade))
                issues.Add(QuickEntryIssues.GradeMissing);
            else if (material is not null)
            {
                var code = TextNormalizer.NormalizeCode(row.Grade);
                var candidates = catalog.Grades.Where(g => g.MaterialId == material.Id && g.NormalizedCode == code).ToList();
                if (!string.IsNullOrWhiteSpace(row.Manufacturer))
                {
                    var variants = Synonyms.MakerVariants(TextNormalizer.Normalize(row.Manufacturer));
                    candidates = candidates.Where(g => g.Maker is not null
                        && variants.Contains(TextNormalizer.Normalize(g.Maker))).ToList();
                }
                if (candidates.Count == 1)
                    grade = candidates[0];
                else
                    issues.Add(candidates.Count == 0 ? QuickEntryIssues.GradeUnknown : QuickEntryIssues.GradeAmbiguous);
            }
        }

        return new Resolved(kind, name.Length == 0 ? null : name, e164, material?.Id, grade?.Id, material?.Code,
            grade is { } gr ? gr.Maker is null ? gr.Code : $"{gr.Code} — {gr.Maker}" : null, issues);
    }

    // ---------------- الدفعات ----------------

    /// <summary>معاينة بلا كتابة: نقص كل صف، والمكرر داخل الدفعة أو بنفس الرقم في النظام.</summary>
    public Task<Result<QuickBatchResult>> ValidateAsync(QuickBatchRequest request, CancellationToken ct) =>
        RunBatchAsync(request, commit: false, ct);

    public Task<Result<QuickBatchResult>> CommitAsync(QuickBatchRequest request, CancellationToken ct) =>
        RunBatchAsync(request, commit: true, ct);

    private async Task<Result<QuickBatchResult>> RunBatchAsync(QuickBatchRequest request, bool commit, CancellationToken ct)
    {
        if (!CanUse)
            return AppError.Forbidden();
        if (request.Method is not (QuickEntryMethods.Paste or QuickEntryMethods.Excel))
            return AppError.Validation("طريقة الإدخال غير معروفة");
        if (request.Method == QuickEntryMethods.Excel && !user.Has(Permissions.ImportRun))
            return AppError.Forbidden("استيراد Excel غير مسموح لهذا المستخدم");
        if (request.Audience is not (QuickEntryAudience.Customers or QuickEntryAudience.Suppliers or QuickEntryAudience.Mixed))
            return AppError.Validation("حدد العملاء أو الموردين أو الاثنين");
        if (request.Rows is not { Count: > 0 } || request.Rows.Count > MaxRows)
            return AppError.Validation($"عدد الصفوف من 1 إلى {MaxRows}", "quick.rows");
        if (request.Rows.Any(r => r.Id == Guid.Empty) || request.Rows.Select(r => r.Id).Distinct().Count() != request.Rows.Count)
            return AppError.Validation("معرفات الصفوف مطلوبة وغير مكررة", "quick.row_ids");

        if (commit)
        {
            if (request.Id == Guid.Empty)
                return AppError.Validation("معرف الدفعة مطلوب");
            var existing = await db.ImportBatches.AsNoTracking().FirstOrDefaultAsync(b => b.Id == request.Id, ct);
            if (existing is not null)
            {
                // إعادة إرسال نفس الدفعة (انقطاع اتصال أو ضغط مزدوج): النتيجة المحفوظة دون أي تكرار.
                if (existing.CreatedBy != user.UserId || existing.Method is null)
                    return AppError.Conflict("quick.id_taken", "معرف الدفعة مستخدم بالفعل");
                return await BatchResultAsync(existing, ct);
            }
            if (await db.ImportEntries.AnyAsync(e => request.Rows.Select(r => r.Id).Contains(e.Id), ct))
                return AppError.Conflict("quick.id_taken", "معرف صف مستخدم بالفعل");
        }

        var catalog = await LoadCatalogAsync(ct);
        var resolved = request.Rows.Select(r => (Row: r, Res: Resolve(r, request.Audience, catalog))).ToList();

        // الأرقام الموجودة في النظام (لكشف التكرار قبل الإنشاء؛ الإنشاء نفسه يتحقق مرة أخرى).
        var phones = resolved.Select(x => x.Res.E164).OfType<string>().Distinct().ToList();
        var owners = await (
                from ph in db.PartyPhones.AsNoTracking()
                join p in db.Parties.AsNoTracking() on ph.PartyId equals p.Id
                where phones.Contains(ph.E164) && p.DeletedAt == null
                select new { ph.E164, Party = p })
            .ToListAsync(ct);

        var results = new List<QuickRowResult>();
        var seen = new Dictionary<(string Kind, string Phone), int>();
        foreach (var (row, res) in resolved)
        {
            QuickRowResult Result(string status, string? note = null, Guid? dupId = null, string? dupName = null) =>
                new(row.Id, row.Row, status, res.Kind, res.Issues, res.MaterialId, res.GradeId, res.MaterialCode,
                    res.GradeLabel, null, dupId, dupName, note);

            if (res.Issues.Count > 0)
            {
                results.Add(Result(ImportEntryStatus.Pending));
                continue;
            }
            if (!CanCreateKind(res.Kind!))
            {
                results.Add(Result(ImportEntryStatus.Failed,
                    res.Kind == QuickEntryAudience.Suppliers ? "لا تملك صلاحية إضافة موردين" : "لا تملك صلاحية إضافة عملاء"));
                continue;
            }
            if (seen.TryGetValue((res.Kind!, res.E164!), out var firstRow))
            {
                results.Add(Result(ImportEntryStatus.Duplicate, $"مكرر في نفس الدفعة (الصف {firstRow})"));
                continue;
            }
            seen[(res.Kind!, res.E164!)] = row.Row;
            var owner = owners.FirstOrDefault(o => o.E164 == res.E164)?.Party;
            if (owner is not null)
            {
                var visible = await access.CanViewAsync(owner, ct);
                var sameKind = res.Kind == QuickEntryAudience.Customers ? owner.IsCustomer : owner.IsSupplier;
                results.Add(visible
                    ? Result(ImportEntryStatus.Duplicate, sameKind
                        ? $"الرقم مسجل بالفعل باسم «{owner.Name}»"
                        : $"الرقم مسجل باسم «{owner.Name}» ك{(owner.IsCustomer ? "عميل" : "مورد")}", owner.Id, owner.Name)
                    : Result(ImportEntryStatus.Duplicate, "هذا الرقم مسجل بالفعل في النظام. تواصل مع الإدارة"));
                continue;
            }
            results.Add(Result("ready"));
        }

        if (!commit)
            return Summarize(request.Id, false, results);

        var now = clock.GetUtcNow();
        var batch = new ImportBatch
        {
            Id = request.Id,
            Kind = "quick",
            FileSha256 = "",
            Summary = "{}",
            Method = request.Method,
            Audience = request.Audience,
            FileName = request.FileName is { Length: > 0 } f ? f[..Math.Min(f.Length, 200)] : null,
            RowCount = request.Rows.Count,
            CreatedBy = user.UserId,
            CreatedAt = now,
            Status = "processed",
        };
        db.ImportBatches.Add(batch);
        var entries = new Dictionary<Guid, ImportEntry>();
        foreach (var (row, res) in resolved)
        {
            var r = results.First(x => x.Id == row.Id);
            var entry = new ImportEntry
            {
                Id = row.Id,
                BatchId = batch.Id,
                RowNumber = row.Row,
                Kind = res.Kind,
                Name = Cut(row.Name, 200),
                Phone = Cut(row.Phone, 40),
                MaterialText = Cut(row.Material, 100),
                GradeText = Cut(row.Grade, 100),
                ManufacturerText = Cut(row.Manufacturer, 120),
                MaterialId = res.MaterialId,
                GradeId = res.GradeId,
                Status = r.Status == "ready" ? ImportEntryStatus.Pending : r.Status,
                DuplicateOfId = r.DuplicateOfId,
                Note = Cut(r.Note, 500),
                CreatedBy = user.UserId,
                CreatedAt = now,
                UpdatedBy = user.UserId,
                UpdatedAt = now,
            };
            entries[row.Id] = entry;
            db.ImportEntries.Add(entry);
        }
        db.Audit(user, clock, "quick.batch", "import", batch.Id,
            new { request.Method, request.Audience, rows = request.Rows.Count });
        await db.SaveChangesAsync(ct);

        // الصفوف الجاهزة: نفس خدمة التسجيل اليدوي (صلاحيات، تكرار، اسم مشابه، تدقيق، المنشئ من الجلسة).
        foreach (var (row, res) in resolved)
        {
            if (results.First(x => x.Id == row.Id).Status != "ready")
                continue;
            await PromoteAsync(entries[row.Id], res, confirmSimilar: false, ct);
        }
        await RecountAsync(batch, ct);
        return await BatchResultAsync(batch, ct);
    }

    private static string? Cut(string? value, int max) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().Length > max ? value.Trim()[..max] : value.Trim();

    /// <summary>إنشاء السجل بمعرف الصف؛ إعادة المحاولة تعيد نفس السجل (لا تكرار).</summary>
    private async Task<AppError?> PromoteAsync(ImportEntry entry, Resolved res, bool confirmSimilar, CancellationToken ct)
    {
        var customer = res.Kind == QuickEntryAudience.Customers;
        var spec = new[] { (res.MaterialId!.Value, res.GradeId!.Value) };
        var created = await parties.CreateAsync(new CreatePartyRequest(entry.Id, res.Name!, customer, !customer,
            [new PhoneInput(res.E164!)],
            Interests: customer ? spec.Select(s => new InterestInput(s.Item1, GradeId: s.Item2)).ToList() : null,
            Products: customer ? null : spec.Select(s => new ProductInput(s.Item1, GradeId: s.Item2)).ToList(),
            ConfirmSimilar: confirmSimilar), ct);

        var now = clock.GetUtcNow();
        entry.UpdatedAt = now;
        entry.UpdatedBy = user.UserId;
        entry.MaterialId = res.MaterialId;
        entry.GradeId = res.GradeId;
        if (created.IsSuccess)
        {
            entry.Status = ImportEntryStatus.Completed;
            entry.PartyId = created.Value!.Id;
            entry.CreatedParty = true;
            entry.DuplicateOfId = null;
            entry.Note = null;
            await db.SaveChangesAsync(ct);
            return null;
        }

        var error = created.Error!;
        switch (error.Code)
        {
            case "party.duplicate_phone" when error.Data is DuplicatePartyInfo dup:
                entry.Status = ImportEntryStatus.Duplicate;
                entry.DuplicateOfId = dup.PartyId;
                entry.Note = Cut($"الرقم مسجل بالفعل باسم «{dup.Name}»", 500);
                break;
            case "party.similar" when error.Data is IEnumerable<SimilarParty> similar:
                entry.Status = ImportEntryStatus.Duplicate;
                entry.DuplicateOfId = similar.FirstOrDefault()?.PartyId;
                entry.Note = Cut($"اسم مشابه لسجل موجود: {string.Join("، ", similar.Select(s => s.Name))}", 500);
                break;
            case "party.duplicate_phone" or "party.duplicate_phone_hidden" or "party.similar" or "party.similar_hidden":
                entry.Status = ImportEntryStatus.Duplicate;
                entry.Note = Cut(error.Message, 500);
                break;
            case "forbidden":
                entry.Status = ImportEntryStatus.Failed;
                entry.Note = Cut(error.Message, 500);
                break;
            default:
                entry.Status = ImportEntryStatus.Pending;
                entry.Note = Cut(error.Message, 500);
                break;
        }
        await db.SaveChangesAsync(ct);
        return error;
    }

    private async Task RecountAsync(ImportBatch batch, CancellationToken ct)
    {
        var statuses = await db.ImportEntries.Where(e => e.BatchId == batch.Id).Select(e => e.Status).ToListAsync(ct);
        batch.CreatedCount = statuses.Count(s => s == ImportEntryStatus.Completed);
        batch.PendingCount = statuses.Count(s => s == ImportEntryStatus.Pending);
        batch.DuplicateCount = statuses.Count(s => s == ImportEntryStatus.Duplicate);
        batch.FailedCount = statuses.Count(s => s == ImportEntryStatus.Failed);
        batch.Summary = JsonSerializer.Serialize(new
        {
            batch.CreatedCount, batch.PendingCount, batch.DuplicateCount, batch.FailedCount,
        }, Json);
        await db.SaveChangesAsync(ct);
    }

    private async Task<QuickBatchResult> BatchResultAsync(ImportBatch batch, CancellationToken ct)
    {
        var catalog = await LoadCatalogAsync(ct);
        var entries = await db.ImportEntries.AsNoTracking().Where(e => e.BatchId == batch.Id)
            .OrderBy(e => e.RowNumber).ToListAsync(ct);
        var names = await DuplicateNamesAsync(entries, ct);
        var rows = entries.Select(e =>
        {
            var res = Resolve(ToRow(e), e.Kind ?? batch.Audience ?? QuickEntryAudience.Mixed, catalog);
            return new QuickRowResult(e.Id, e.RowNumber, e.Status, e.Kind, e.Status == ImportEntryStatus.Completed ? [] : res.Issues,
                e.MaterialId ?? res.MaterialId, e.GradeId ?? res.GradeId, res.MaterialCode, res.GradeLabel, e.PartyId,
                e.DuplicateOfId, e.DuplicateOfId is { } d ? names.GetValueOrDefault(d) : null, e.Note);
        }).ToList();
        return Summarize(batch.Id, true, rows);
    }

    private static QuickBatchResult Summarize(Guid id, bool committed, List<QuickRowResult> rows) => new(id, committed,
        rows.Count,
        rows.Count(r => r.Status is ImportEntryStatus.Completed or "ready"),
        rows.Count(r => r.Status == ImportEntryStatus.Pending),
        rows.Count(r => r.Status == ImportEntryStatus.Duplicate),
        rows.Count(r => r.Status == ImportEntryStatus.Failed), rows);

    private static QuickEntryRow ToRow(ImportEntry e) => new(e.Id, e.RowNumber, e.Kind, e.Name, e.Phone, e.MaterialText,
        e.GradeText, e.ManufacturerText, e.MaterialId, e.GradeId);

    /// <summary>أسماء السجلات المرشحة كمكررة، للظاهر منها للمستخدم فقط.</summary>
    private async Task<Dictionary<Guid, string>> DuplicateNamesAsync(IEnumerable<ImportEntry> entries, CancellationToken ct)
    {
        var ids = entries.Select(e => e.DuplicateOfId).OfType<Guid>().Distinct().ToList();
        if (ids.Count == 0)
            return [];
        return await access.Visible(db.Parties.AsNoTracking()).Where(p => ids.Contains(p.Id) && p.DeletedAt == null)
            .ToDictionaryAsync(p => p.Id, p => p.Name, ct);
    }

    // ---------------- بانتظار الاستكمال ----------------

    /// <summary>الصف لصاحبه، ولمن يرى كل سجلات نوعه (والمورد لمن يرى الموردين فقط).</summary>
    private IQueryable<ImportEntry> VisibleEntries()
    {
        var uid = user.UserId;
        var allCustomers = access.ViewAllCustomers;
        var suppliers = access.CanSeeSuppliers;
        return db.ImportEntries.Where(e => e.CreatedBy == uid
            || (allCustomers && e.Kind == QuickEntryAudience.Customers)
            || (suppliers && e.Kind == QuickEntryAudience.Suppliers)
            || (allCustomers && suppliers && e.Kind == null));
    }

    private bool CanEditEntry(ImportEntry e) => e.CreatedBy == user.UserId || access.CanManage;

    public async Task<Result<PagedResult<PendingEntryDto>>> PendingAsync(PendingQuery query, CancellationToken ct)
    {
        if (!CanUse)
            return AppError.Forbidden();
        var statuses = query.Status is { Length: > 0 } s
            ? s.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : [ImportEntryStatus.Pending, ImportEntryStatus.Duplicate];
        var items = VisibleEntries().AsNoTracking().Where(e => statuses.Contains(e.Status));
        if (query.Kind is { Length: > 0 } kind)
            items = kind == "none" ? items.Where(e => e.Kind == null) : items.Where(e => e.Kind == kind);
        if (query.BatchId is { } batchId)
            items = items.Where(e => e.BatchId == batchId);
        if (query.Q is { Length: > 0 } q)
        {
            var text = q.Trim();
            var digits = new string(text.Where(char.IsAsciiDigit).ToArray()).TrimStart('0');
            items = items.Where(e => (e.Name != null && e.Name.Contains(text))
                || (digits.Length >= 4 && e.Phone != null && e.Phone.Contains(digits)));
        }

        var list = await items.OrderByDescending(e => e.CreatedAt).ThenBy(e => e.RowNumber).Take(MaxRows).ToListAsync(ct);
        var dtos = await ToDtosAsync(list, ct);
        if (query.Issue is { Length: > 0 } issue)
            dtos = dtos.Where(d => d.Issues.Contains(issue)).ToList();
        var take = Math.Clamp(query.Take, 1, 200);
        return new PagedResult<PendingEntryDto>(dtos.Skip(Math.Max(query.Skip, 0)).Take(take).ToList(), dtos.Count);
    }

    private async Task<List<PendingEntryDto>> ToDtosAsync(List<ImportEntry> list, CancellationToken ct)
    {
        var catalog = await LoadCatalogAsync(ct);
        var batchIds = list.Select(e => e.BatchId).Distinct().ToList();
        var batches = await db.ImportBatches.AsNoTracking().Where(b => batchIds.Contains(b.Id))
            .ToDictionaryAsync(b => b.Id, b => (b.Method, b.Audience), ct);
        var userIds = list.Select(e => e.CreatedBy).Distinct().ToList();
        var users = await db.Users.AsNoTracking().Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.DisplayName, ct);
        var names = await DuplicateNamesAsync(list, ct);
        return list.Select(e =>
        {
            var batch = batches.GetValueOrDefault(e.BatchId);
            var res = Resolve(ToRow(e), e.Kind ?? batch.Audience ?? QuickEntryAudience.Mixed, catalog);
            return new PendingEntryDto(e.Id, e.BatchId, batch.Method, e.RowNumber, e.Kind ?? res.Kind, e.Name, e.Phone,
                e.MaterialText, e.GradeText, e.ManufacturerText, e.MaterialId ?? res.MaterialId, e.GradeId ?? res.GradeId,
                res.MaterialCode, res.GradeLabel, e.Status, res.Issues, e.DuplicateOfId,
                e.DuplicateOfId is { } d ? names.GetValueOrDefault(d) : null, e.Note, e.PartyId, e.CreatedAt,
                users.GetValueOrDefault(e.CreatedBy));
        }).ToList();
    }

    private async Task<Result<ImportEntry>> LoadEditableEntryAsync(Guid id, CancellationToken ct)
    {
        var entry = await VisibleEntries().FirstOrDefaultAsync(e => e.Id == id, ct);
        if (entry is null)
            return AppError.NotFound();
        if (!CanEditEntry(entry))
            return AppError.Forbidden("الاستكمال لمن أدخل البيانات أو للمدير");
        return entry;
    }

    /// <summary>حفظ التصحيح دون إنشاء بطاقة (يبقى بانتظار الاستكمال).</summary>
    public async Task<Result<PendingEntryDto>> UpdateAsync(Guid id, PendingUpdate update, CancellationToken ct)
    {
        var loaded = await LoadEditableEntryAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var e = loaded.Value!;
        if (e.Status is ImportEntryStatus.Completed or ImportEntryStatus.Discarded)
            return AppError.Conflict("quick.closed", "هذا الصف مكتمل أو مستبعد");
        e.Kind = update.Kind is QuickEntryAudience.Customers or QuickEntryAudience.Suppliers ? update.Kind : ParseKind(update.Kind);
        if (e.Kind is not null && !CanCreateKind(e.Kind))
            return AppError.Forbidden(e.Kind == QuickEntryAudience.Suppliers ? "لا تملك صلاحية إضافة موردين" : "لا تملك صلاحية إضافة عملاء");
        e.Name = Cut(update.Name, 200);
        e.Phone = Cut(update.Phone, 40);
        e.MaterialText = Cut(update.Material, 100);
        e.GradeText = Cut(update.Grade, 100);
        e.ManufacturerText = Cut(update.Manufacturer, 120);
        e.MaterialId = update.MaterialId;
        e.GradeId = update.GradeId;
        if (e.Status is ImportEntryStatus.Failed)
            e.Status = ImportEntryStatus.Pending;
        e.Touch(user.UserId, clock.GetUtcNow());
        await db.SaveChangesAsync(ct);
        return (await ToDtosAsync([e], ct))[0];
    }

    /// <summary>
    /// إنشاء البطاقة عند اكتمال كل الشروط، مرة واحدة: الصف المكتمل يعيد نفس السجل، والإنشاء بمعرف الصف
    /// فلا يتكرر عند إعادة المحاولة أو إعادة إرسال الطابور.
    /// </summary>
    public async Task<Result<CompletedEntry>> CompleteAsync(Guid id, CompleteEntryRequest request, CancellationToken ct)
    {
        var loaded = await LoadEditableEntryAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var e = loaded.Value!;
        if (e.Status == ImportEntryStatus.Completed && e.PartyId is { } done)
            return new CompletedEntry(e.Id, done, e.CreatedParty);
        if (e.Status == ImportEntryStatus.Discarded)
            return AppError.Conflict("quick.closed", "هذا الصف مستبعد");
        var audience = await db.ImportBatches.Where(b => b.Id == e.BatchId).Select(b => b.Audience).FirstAsync(ct);
        var res = Resolve(ToRow(e), e.Kind ?? audience ?? QuickEntryAudience.Mixed, await LoadCatalogAsync(ct));
        if (res.Issues.Count > 0)
            return new AppError(ErrorKind.Validation, "quick.incomplete", "أكمل البيانات الناقصة أولًا", res.Issues);
        e.Kind = res.Kind;
        var error = await PromoteAsync(e, res, request.ConfirmSimilar, ct);
        if (await db.ImportBatches.FirstOrDefaultAsync(b => b.Id == e.BatchId, ct) is { } batch)
            await RecountAsync(batch, ct);
        return error is null ? new CompletedEntry(e.Id, e.PartyId!.Value, true) : error;
    }

    /// <summary>
    /// مكرر برقم مسجل: إضافة خامته للسجل الموجود (إضافة فقط، بصلاحية الإضافة، وبتأكيد صريح). الاسم
    /// والمنشئ وباقي البيانات لا تتغير. إضافة الدور الآخر لنفس الشركة تحتاج <see cref="MergeEntryRequest.AddRole"/>.
    /// </summary>
    public async Task<Result<CompletedEntry>> MergeAsync(Guid id, MergeEntryRequest request, CancellationToken ct)
    {
        var loaded = await LoadEditableEntryAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var e = loaded.Value!;
        if (e.Status == ImportEntryStatus.Completed && e.PartyId is { } done)
            return new CompletedEntry(e.Id, done, e.CreatedParty);
        if (e.Status != ImportEntryStatus.Duplicate || e.DuplicateOfId is not { } targetId)
            return AppError.Validation("لا يوجد سجل موجود مرشح لهذا الصف", "quick.no_target");
        var audience = await db.ImportBatches.Where(b => b.Id == e.BatchId).Select(b => b.Audience).FirstAsync(ct);
        var res = Resolve(ToRow(e), e.Kind ?? audience ?? QuickEntryAudience.Mixed, await LoadCatalogAsync(ct));
        var blocking = res.Issues.Where(i => i is not (QuickEntryIssues.NameMissing or QuickEntryIssues.NameInvalid)).ToList();
        if (blocking.Count > 0)
            return new AppError(ErrorKind.Validation, "quick.incomplete", "أكمل البيانات الناقصة أولًا", blocking);

        var target = await access.LoadForAddAsync(targetId, ct);
        if (!target.IsSuccess)
            return target.Error!;
        var party = target.Value!;
        var customer = res.Kind == QuickEntryAudience.Customers;
        if (customer ? !party.IsCustomer : !party.IsSupplier)
        {
            if (!request.AddRole)
                return AppError.Conflict("quick.role_needed",
                    $"«{party.Name}» مسجل ك{(party.IsCustomer ? "عميل" : "مورد")}. أكد إضافته ك{(customer ? "عميل" : "مورد")} لنفس الشركة");
            var role = await parties.AddRoleAsync(party.Id, new AddRoleRequest(customer, !customer), ct);
            if (!role.IsSuccess)
                return role.Error!;
        }
        if (customer)
        {
            var added = await parties.AddInterestAsync(party.Id, new InterestInput(res.MaterialId!.Value, GradeId: res.GradeId), ct);
            if (!added.IsSuccess)
                return added.Error!;
        }
        else
        {
            var added = await parties.AddProductAsync(party.Id, new ProductInput(res.MaterialId!.Value, GradeId: res.GradeId), ct);
            if (!added.IsSuccess)
                return added.Error!;
        }

        e.Status = ImportEntryStatus.Completed;
        e.PartyId = party.Id;
        e.CreatedParty = false;
        e.Kind = res.Kind;
        e.Note = "أُضيفت الخامة لسجل موجود";
        e.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "quick.merged", "party", party.Id, new { entry = e.Id, batch = e.BatchId });
        await db.SaveChangesAsync(ct);
        if (await db.ImportBatches.FirstOrDefaultAsync(b => b.Id == e.BatchId, ct) is { } batch)
            await RecountAsync(batch, ct);
        return new CompletedEntry(e.Id, party.Id, false);
    }

    /// <summary>استبعاد صف (يبقى في سجل الدفعة ولا يُحذف).</summary>
    public async Task<Result<bool>> DiscardAsync(Guid id, CancellationToken ct)
    {
        var loaded = await LoadEditableEntryAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var e = loaded.Value!;
        if (e.Status == ImportEntryStatus.Completed)
            return AppError.Conflict("quick.closed", "هذا الصف أصبح بطاقة بالفعل");
        e.Status = ImportEntryStatus.Discarded;
        e.Touch(user.UserId, clock.GetUtcNow());
        await db.SaveChangesAsync(ct);
        if (await db.ImportBatches.FirstOrDefaultAsync(b => b.Id == e.BatchId, ct) is { } batch)
            await RecountAsync(batch, ct);
        return true;
    }

    public async Task<Result<(byte[] Content, string FileName)>> ExportPendingAsync(PendingQuery query, CancellationToken ct)
    {
        var list = await PendingAsync(query with { Skip = 0, Take = 200 }, ct);
        if (!list.IsSuccess)
            return list.Error!;
        var all = new List<PendingEntryDto>(list.Value!.Items);
        for (var skip = all.Count; skip < list.Value.Total; skip += 200)
            all.AddRange((await PendingAsync(query with { Skip = skip, Take = 200 }, ct)).Value!.Items);
        var rows = all.Select(d => (IReadOnlyList<object?>)
        [
            d.Kind switch { QuickEntryAudience.Customers => "عميل", QuickEntryAudience.Suppliers => "مورد", _ => "غير محدد" },
            d.Name, d.Phone, d.MaterialCode ?? d.Material, d.GradeLabel ?? d.Grade,
            d.Status == ImportEntryStatus.Duplicate ? "مكرر محتمل" : "بانتظار الاستكمال",
            string.Join("، ", d.Issues.Select(IssueLabel)), d.Note, d.CreatedByName,
        ]);
        var content = XlsxWriter.WriteSheets([new XlsxSheet("بانتظار الاستكمال",
            ["النوع", "الاسم", "الهاتف", "الخامة", "Grade", "الحالة", "الناقص", "ملاحظة", "أدخله"], rows,
            [10, 32, 16, 12, 20, 16, 40, 30, 18])]);
        db.Audit(user, clock, "export.pending", "import", Guid.Empty, new { rows = all.Count });
        await db.SaveChangesAsync(ct);
        return (content, $"pending-{BusinessClock.Today(clock):yyyy-MM-dd}.xlsx");
    }

    public static string IssueLabel(string issue) => issue switch
    {
        QuickEntryIssues.NameMissing => "الاسم",
        QuickEntryIssues.NameInvalid => "الاسم غير صالح",
        QuickEntryIssues.PhoneMissing => "رقم الموبايل",
        QuickEntryIssues.PhoneInvalid => "رقم موبايل غير صحيح",
        QuickEntryIssues.MaterialMissing => "الخامة",
        QuickEntryIssues.MaterialUnknown => "خامة غير موجودة في الكتالوج",
        QuickEntryIssues.GradeMissing => "Grade",
        QuickEntryIssues.GradeUnknown => "Grade غير موجود لهذه الخامة",
        QuickEntryIssues.GradeAmbiguous => "Grade مسجل لأكثر من شركة — حدده",
        QuickEntryIssues.KindMissing => "نوع السجل (عميل/مورد)",
        _ => issue,
    };

    // ---------------- سجل الدفعات والتراجع ----------------

    public async Task<Result<IReadOnlyList<QuickBatchSummary>>> BatchesAsync(CancellationToken ct)
    {
        if (!CanUse)
            return AppError.Forbidden();
        var uid = user.UserId;
        var all = access.CanManage;
        var batches = await db.ImportBatches.AsNoTracking()
            .Where(b => b.Method != null && (all || b.CreatedBy == uid))
            .OrderByDescending(b => b.CreatedAt).Take(50).ToListAsync(ct);
        var userIds = batches.Select(b => b.CreatedBy).Distinct().ToList();
        var users = await db.Users.AsNoTracking().Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.DisplayName, ct);
        return batches.Select(b => new QuickBatchSummary(b.Id, b.Method, b.Audience, b.FileName, b.RowCount,
            b.CreatedCount, b.PendingCount, b.DuplicateCount, b.FailedCount, b.Status, b.CreatedAt,
            users.GetValueOrDefault(b.CreatedBy))).ToList();
    }

    /// <summary>
    /// تراجع آمن للمدير العام: يحذف (حذفًا آمنًا قابلًا للاستعادة) فقط السجلات التي أنشأتها الدفعة ولم يُضف
    /// إليها أو يُعدّل فيها شيء بعدها، ويستبعد صفوفها المعلقة. ما لا يمكن عكسه يُعرض بسببه ولا يُلمس، والإضافات
    /// لسجلات موجودة لا تُعكس تلقائيًا.
    /// </summary>
    public async Task<Result<UndoResult>> UndoAsync(Guid batchId, CancellationToken ct)
    {
        if (!access.CanManage)
            return AppError.Forbidden("التراجع عن دفعة للمدير العام فقط");
        var batch = await db.ImportBatches.FirstOrDefaultAsync(b => b.Id == batchId && b.Method != null, ct);
        if (batch is null)
            return AppError.NotFound();
        var entries = await db.ImportEntries.Where(e => e.BatchId == batchId).ToListAsync(ct);
        var blocked = new List<UndoBlocked>();
        var reversed = 0;
        var discarded = 0;
        var now = clock.GetUtcNow();
        foreach (var e in entries)
        {
            if (e.Status is ImportEntryStatus.Pending or ImportEntryStatus.Duplicate or ImportEntryStatus.Failed)
            {
                e.Status = ImportEntryStatus.Discarded;
                e.Note = "استُبعد بالتراجع عن الدفعة";
                e.Touch(user.UserId, now);
                discarded++;
                continue;
            }
            if (e.Status != ImportEntryStatus.Completed || e.PartyId is not { } partyId)
                continue;
            var party = await db.Parties.AsNoTracking().FirstOrDefaultAsync(p => p.Id == partyId, ct);
            if (party is null || party.DeletedAt is not null)
                continue;
            var reason = !e.CreatedParty ? "أُضيفت الخامة لسجل كان موجودًا قبل الدفعة — لا يُعكس تلقائيًا"
                : party.UpdatedBy != party.CreatedBy || party.UpdatedAt > party.CreatedAt.AddMinutes(1)
                    ? "عُدّل السجل بعد الاستيراد"
                : await db.Orders.AnyAsync(o => o.CustomerId == partyId, ct) ? "مرتبط بطلبات"
                : await db.Supplies.AnyAsync(s => s.SupplierId == partyId, ct) ? "مرتبط بتوريدات"
                : await db.Interactions.AnyAsync(i => i.PartyId == partyId, ct) ? "مسجل له تواصل"
                : await db.PartyContacts.AnyAsync(c => c.PartyId == partyId, ct) ? "أُضيف له موظفون"
                : await db.PartyLocations.AnyAsync(l => l.PartyId == partyId, ct) ? "أُضيفت له مواقع"
                : await db.Attachments.AnyAsync(a => a.PartyId == partyId, ct) ? "أُضيفت له ملفات"
                : null;
            if (reason is not null)
            {
                blocked.Add(new UndoBlocked(partyId, party.Name, reason));
                continue;
            }
            var deleted = await parties.DeleteAsync(partyId, ct);
            if (!deleted.IsSuccess)
            {
                blocked.Add(new UndoBlocked(partyId, party.Name, deleted.Error!.Message));
                continue;
            }
            e.Status = ImportEntryStatus.Discarded;
            e.Note = "أُلغي بالتراجع عن الدفعة (قابل للاستعادة من المحذوفات)";
            e.Touch(user.UserId, now);
            reversed++;
        }
        batch.Status = blocked.Count == 0 ? "undone" : "partially_undone";
        db.Audit(user, clock, "quick.undo", "import", batch.Id, new { reversed, discarded, blocked = blocked.Count });
        await db.SaveChangesAsync(ct);
        await RecountAsync(batch, ct);
        return new UndoResult(reversed, discarded, blocked, batch.Status);
    }

    // ---------------- Excel ----------------

    /// <summary>أوراق الملف بعناوينها وصفوفها، مع تعيين مقترح للأعمدة (يؤكده أو يغيره المستخدم).</summary>
    public async Task<Result<IReadOnlyList<ExcelSheet>>> ReadExcelAsync(Stream file, string? fileName, CancellationToken ct)
    {
        if (!user.Has(Permissions.ImportRun))
            return AppError.Forbidden("استيراد Excel غير مسموح لهذا المستخدم");
        if (fileName is { } n && n.EndsWith(".xls", StringComparison.OrdinalIgnoreCase))
            return AppError.Validation("صيغة Excel القديمة (xls) غير مدعومة. احفظ الملف بصيغة xlsx ثم أعد المحاولة",
                "import.xls");
        using var buffer = new MemoryStream();
        await file.CopyToAsync(buffer, ct);
        if (buffer.Length > ImportService.MaxFileBytes)
            return AppError.Validation("حجم الملف أكبر من 5 ميجابايت");
        buffer.Position = 0;
        List<(string Name, List<string[]> Rows)> sheets;
        try
        {
            sheets = XlsxReader.ReadSheets(buffer);
        }
        catch (InvalidDataException e)
        {
            return AppError.Validation(e.Message, "import.invalid_file");
        }
        var result = new List<ExcelSheet>();
        foreach (var (name, rows) in sheets)
        {
            if (rows.Count == 0)
                continue;
            if (rows.Count - 1 > MaxRows)
                return AppError.Validation($"الحد الأقصى {MaxRows} صف في الورقة الواحدة", "import.too_many_rows");
            var headers = rows[0].Select(h => h.Trim()).ToList();
            var width = rows.Max(r => r.Length);
            while (headers.Count < width)
                headers.Add("");
            var data = rows.Skip(1)
                .Where(r => r.Any(c => c.Length > 0))
                .Select(r => (IReadOnlyList<string>)Enumerable.Range(0, width).Select(i => i < r.Length ? r[i] : "").ToList())
                .ToList();
            result.Add(new ExcelSheet(name, headers, data, SuggestMapping(headers)));
        }
        if (result.Count == 0)
            return AppError.Validation("الملف لا يحتوي على بيانات", "import.empty");
        return result;
    }

    /// <summary>تعيين مقترح بأسماء الأعمدة فقط (التطابق التام ثم الاحتواء)؛ لا يُستخدم عمود لحقلين.</summary>
    public static Dictionary<string, int> SuggestMapping(IReadOnlyList<string> headers)
    {
        var normalized = headers.Select(TextNormalizer.Normalize).ToList();
        var map = new Dictionary<string, int>();
        foreach (var exact in new[] { true, false })
            foreach (var (field, names) in Columns)
            {
                if (map.ContainsKey(field))
                    continue;
                var keys = names.Select(TextNormalizer.Normalize).ToList();
                var col = Enumerable.Range(0, normalized.Count).FirstOrDefault(i => !map.ContainsValue(i)
                    && normalized[i].Length > 0
                    && (exact ? keys.Contains(normalized[i]) : keys.Any(k => k.Length >= 4 && normalized[i].Contains(k))), -1);
                if (col >= 0)
                    map[field] = col;
            }
        return map;
    }

    // ---------------- التصدير الذكي ----------------

    /// <summary>
    /// استعلام واحد لكل صيغ التصدير (المعاينة، Excel، PDF، الطباعة): الظاهر للمستخدم فقط، والموردون لمن
    /// يطّلع عليهم فقط. صف لكل ارتباط خامة/Grade مطابق؛ عند الفلترة لا تظهر الارتباطات غير المطابقة.
    /// </summary>
    public async Task<Result<ExportResult>> ExportAsync(ExportRequest request, CancellationToken ct)
    {
        if (!user.Has(Permissions.ReportsExport))
            return AppError.Forbidden("تصدير القوائم غير مسموح لهذا المستخدم");
        var wantCustomers = request.Audience is QuickEntryAudience.Customers or QuickEntryAudience.Mixed;
        var wantSuppliers = request.Audience is QuickEntryAudience.Suppliers or QuickEntryAudience.Mixed;
        if (!wantCustomers && !wantSuppliers)
            return AppError.Validation("حدد العملاء أو الموردين أو الاثنين");
        if (wantSuppliers && !access.CanSeeSuppliers)
            return AppError.Forbidden("بيانات الموردين للإدارة فقط");
        if (request.GradeId is { } g && request.MaterialId is { } m
            && !await db.Grades.AnyAsync(x => x.Id == g && x.MaterialId == m, ct))
            return AppError.Validation("الـ Grade لا يتبع الخامة المختارة");
        if (request.GradeId is not null && request.MaterialId is null)
            return AppError.Validation("اختر الخامة مع الـ Grade");

        var materials = await db.Materials.AsNoTracking().ToDictionaryAsync(x => x.Id, x => x.Code, ct);
        var grades = await (
                from gr in db.Grades.AsNoTracking()
                join mk in db.Manufacturers.AsNoTracking() on gr.ManufacturerId equals mk.Id into mj
                from mk in mj.DefaultIfEmpty()
                select new { gr.Id, gr.Code, Maker = mk == null ? null : mk.Name })
            .ToDictionaryAsync(x => x.Id, ct);
        var filtered = request.MaterialId is not null;

        async Task<List<ExportRow>> RowsAsync(bool customers)
        {
            var visible = access.VisibleAs(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null), customers, !customers)
                .Where(p => customers ? p.IsCustomer : p.IsSupplier);
            var people = await visible
                .Select(p => new
                {
                    p.Id, p.Name,
                    Phone = p.Phones.OrderByDescending(ph => ph.IsPrimary).Select(ph => ph.E164).FirstOrDefault(),
                })
                .ToListAsync(ct);
            var ids = people.Select(p => p.Id).ToList();
            var specs = customers
                ? await db.CustomerInterests.AsNoTracking().Where(i => ids.Contains(i.PartyId))
                    .Select(i => new { i.PartyId, i.MaterialId, i.GradeId, i.OpenSpec }).ToListAsync(ct)
                : await db.SupplierProducts.AsNoTracking().Where(p => ids.Contains(p.PartyId) && p.IsActive)
                    .Select(p => new { p.PartyId, p.MaterialId, p.GradeId, OpenSpec = false }).ToListAsync(ct);
            var bySpec = specs
                .Where(s => request.MaterialId is null || s.MaterialId == request.MaterialId)
                .Where(s => request.GradeId is null || s.GradeId == request.GradeId)
                .GroupBy(s => s.PartyId).ToDictionary(x => x.Key, x => x.DistinctBy(s => (s.MaterialId, s.GradeId)).ToList());
            var kind = customers ? QuickEntryAudience.Customers : QuickEntryAudience.Suppliers;
            var rows = new List<ExportRow>();
            foreach (var p in people.OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                var phone = p.Phone is { } e && e.StartsWith("+20", StringComparison.Ordinal) ? "0" + e[3..] : p.Phone;
                if (bySpec.TryGetValue(p.Id, out var list))
                {
                    foreach (var s in list)
                    {
                        var gr = s.GradeId is { } gid ? grades.GetValueOrDefault(gid) : null;
                        rows.Add(new ExportRow(kind, p.Id, p.Name, phone, materials.GetValueOrDefault(s.MaterialId),
                            gr?.Code ?? (s.OpenSpec ? "أي Grade" : null), gr?.Maker));
                    }
                }
                else if (!filtered)
                {
                    rows.Add(new ExportRow(kind, p.Id, p.Name, phone, null, null, null));
                }
            }
            return rows;
        }

        var customerRows = wantCustomers ? await RowsAsync(true) : [];
        var supplierRows = wantSuppliers ? await RowsAsync(false) : [];
        return new ExportResult(request.Audience, customerRows.Select(r => r.PartyId).Distinct().Count(),
            supplierRows.Select(r => r.PartyId).Distinct().Count(), [.. customerRows, .. supplierRows]);
    }

    public async Task<Result<(byte[] Content, string FileName)>> ExportExcelAsync(ExportRequest request, CancellationToken ct)
    {
        var result = await ExportAsync(request, ct);
        if (!result.IsSuccess)
            return result.Error!;
        var data = result.Value!;
        string[] headers = ["الاسم", "رقم الهاتف", "الخامة", "Grade", "الشركة المصنعة"];
        int[] widths = [36, 16, 12, 18, 20];
        IEnumerable<IReadOnlyList<object?>> Sheet(string kind) => data.Rows.Where(r => r.Kind == kind)
            .Select(r => (IReadOnlyList<object?>)[r.Name, r.Phone, r.Material, r.Grade, r.Manufacturer]);
        var sheets = new List<XlsxSheet>();
        if (request.Audience is QuickEntryAudience.Customers or QuickEntryAudience.Mixed)
            sheets.Add(new XlsxSheet("العملاء", headers, Sheet(QuickEntryAudience.Customers).ToList(), widths));
        if (request.Audience is QuickEntryAudience.Suppliers or QuickEntryAudience.Mixed)
            sheets.Add(new XlsxSheet("الموردون", headers, Sheet(QuickEntryAudience.Suppliers).ToList(), widths));
        db.Audit(user, clock, "export.quick", "export", Guid.Empty,
            new { request.Audience, request.MaterialId, request.GradeId, rows = data.Rows.Count });
        await db.SaveChangesAsync(ct);
        return (XlsxWriter.WriteSheets(sheets), $"export-{BusinessClock.Today(clock):yyyy-MM-dd}.xlsx");
    }
}
