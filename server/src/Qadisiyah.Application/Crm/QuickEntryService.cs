using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Crm;

/// <summary>
/// أكواد نتيجة التحقق. <b>العوائق</b> (الاسم، الموبايل، الخامة، النوع) تمنع إنشاء البطاقة وتُرسل في
/// <c>issues</c>. <b>التحذيرات</b> (كل ما يخص الـ Grade والمنشأ) لا تمنعه وتُرسل في <c>warnings</c>؛ منها
/// تحذيرات <b>المراجعة</b> (<see cref="Review"/>) التي تحتاج تأكيدًا صريحًا من المستخدم قبل الحفظ.
/// </summary>
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

    /// <summary>Grade غير موجود في الكتالوج لهذه الخامة: يُحفظ نصًا «غير موثق».</summary>
    public const string GradeUnverified = "grade_unverified";

    /// <summary>الـ Grade مسجل لخامة أخرى فقط: لا يُربط بخامة خاطئة، ويُحفظ نصًا بعد المراجعة.</summary>
    public const string GradeMaterialMismatch = "grade_material_mismatch";

    /// <summary>الـ Grade موجود لكن الشركة المصنعة المكتوبة لا تطابقه: لا تخمين، ويُحفظ نصًا بعد المراجعة.</summary>
    public const string GradeManufacturerMismatch = "grade_manufacturer_mismatch";

    /// <summary>بلد المنشأ غير موجود في القائمة: يبقى نصه في صف الإدخال فقط.</summary>
    public const string OriginUnknown = "origin_unknown";

    /// <summary>تحذيرات تحتاج مراجعة وتأكيدًا صريحًا قبل الحفظ.</summary>
    public static readonly IReadOnlySet<string> Review = new HashSet<string>
    {
        GradeAmbiguous, GradeMaterialMismatch, GradeManufacturerMismatch,
    };
}

/// <summary>حالة صف في المعاينة إضافة إلى حالات <see cref="ImportEntryStatus"/>.</summary>
public static class QuickRowStatus
{
    public const string Ready = "ready";

    /// <summary>بلا عوائق لكن بتحذير مراجعة لم يؤكده المستخدم؛ يُحفظ «بانتظار الاستكمال» ولا تُنشأ بطاقته.</summary>
    public const string NeedsReview = "needs_review";
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
/// <param name="ReviewAcknowledged">أكد المستخدم مراجعة تحذيرات الـ Grade الملتبس لهذا الصف.</param>
public sealed record QuickEntryRow(Guid Id, int Row, string? Kind, string? Name, string? Phone, string? Material,
    string? Grade, string? Manufacturer = null, Guid? MaterialId = null, Guid? GradeId = null, string? Origin = null,
    bool ReviewAcknowledged = false);

public sealed record QuickBatchRequest(Guid Id, string Method, string Audience, IReadOnlyList<QuickEntryRow> Rows,
    string? FileName = null);

/// <param name="Status">ready أو needs_review (معاينة) أو completed أو pending أو duplicate أو failed.</param>
/// <param name="Issues">العوائق فقط.</param>
/// <param name="Warnings">تحذيرات لا تمنع الحفظ (منها تحذيرات المراجعة).</param>
/// <param name="NeedsReview">بتحذير مراجعة لم يُؤكَّد بعد.</param>
/// <param name="ErrorCode">كود خطأ معالجة غير متوقع (يختلف عن النقص والتحذير).</param>
public sealed record QuickRowResult(Guid Id, int Row, string Status, string? Kind, IReadOnlyList<string> Issues,
    Guid? MaterialId, Guid? GradeId, string? MaterialCode, string? GradeLabel, Guid? PartyId,
    Guid? DuplicateOfId, string? DuplicateName, string? Note, IReadOnlyList<string>? Warnings = null,
    string? UnverifiedGrade = null, bool NeedsReview = false, string? ErrorCode = null);

public sealed record QuickBatchResult(Guid BatchId, bool Committed, int Total, int Created, int Pending, int Duplicate,
    int Failed, IReadOnlyList<QuickRowResult> Rows);

public sealed record PendingEntryDto(Guid Id, Guid BatchId, string? Method, int Row, string? Kind, string? Name,
    string? Phone, string? Material, string? Grade, string? Manufacturer, Guid? MaterialId, Guid? GradeId,
    string? MaterialCode, string? GradeLabel, string Status, IReadOnlyList<string> Issues, Guid? DuplicateOfId,
    string? DuplicateName, string? Note, Guid? PartyId, DateTimeOffset CreatedAt, string? CreatedByName,
    string? Origin = null, IReadOnlyList<string>? Warnings = null, string? UnverifiedGrade = null,
    bool NeedsReview = false, bool ReviewAcknowledged = false, string? ErrorCode = null);

/// <param name="ReviewAcknowledged">null = يبقى التأكيد كما هو ما لم تتغير الخامة أو الـ Grade أو الشركة.</param>
public sealed record PendingUpdate(string? Kind, string? Name, string? Phone, string? Material, string? Grade,
    string? Manufacturer = null, Guid? MaterialId = null, Guid? GradeId = null, string? Origin = null,
    bool? ReviewAcknowledged = null);

public sealed record PendingQuery(string? Q = null, string? Kind = null, Guid? BatchId = null, string? Issue = null,
    string? Status = null, int Skip = 0, int Take = 50);

/// <param name="AcknowledgeReview">تأكيد صريح لحفظ Grade ملتبس كنص غير موثق.</param>
public sealed record CompleteEntryRequest(bool ConfirmSimilar = false, bool AcknowledgeReview = false);

public sealed record MergeEntryRequest(bool AddRole = false, bool AcknowledgeReview = false);

public sealed record CompletedEntry(Guid EntryId, Guid PartyId, bool Created);

/// <summary>أسباب حماية صف «بانتظار الاستكمال» من الاستبعاد.</summary>
public static class DiscardReasons
{
    /// <summary>أصبح بطاقة.</summary>
    public const string Completed = "completed";

    /// <summary>مرتبط بسجل عميل/مورد (أُنشئ أو أُضيف إليه).</summary>
    public const string LinkedParty = "linked_party";

    /// <summary>توجد بطاقة بمعرف الصف رغم أن حالته لم تُحدَّث (إنشاء انقطع قبل اكتماله).</summary>
    public const string UncertainPromotion = "uncertain_promotion";

    /// <summary>حُفظ جاهزًا ولم تنتهِ محاولة إنشاء بطاقته؛ إعادة إرسال الدفعة قد تكملها.</summary>
    public const string AwaitingPromotion = "awaiting_promotion";

    /// <summary>ظاهر للمستخدم لكنه ليس صاحبه ولا يملك صلاحية إدارة السجلات.</summary>
    public const string Forbidden = "forbidden";

    /// <summary>غير موجود أو غير ظاهر للمستخدم (لا يُكشف وجوده).</summary>
    public const string NotFound = "not_found";
}

/// <param name="Outcome">discarded أو already_discarded أو skipped.</param>
public sealed record DiscardOutcome(Guid Id, string Outcome, string? Reason = null);

public sealed record DiscardManyRequest(IReadOnlyList<Guid>? Ids);

/// <param name="RemainingPending">عدد «بانتظار الاستكمال» الظاهر للمستخدم بعد العملية (قيمة العداد).</param>
public sealed record DiscardManyResult(int Discarded, int AlreadyDiscarded, IReadOnlyList<DiscardOutcome> Skipped,
    int RemainingPending);

/// <summary>
/// حذف كل المؤهل: <paramref name="Preview"/> يعيد الأعداد ورمز اللقطة دون أي كتابة؛ التنفيذ يتطلب نفس
/// الرمز، فإن تغيرت القائمة بعد المعاينة يُرفض دون أي استبعاد.
/// </summary>
public sealed record DiscardAllRequest(bool Preview = true, string? Token = null, string? Kind = null,
    Guid? BatchId = null);

/// <param name="Eligible">ما سيُستبعد (أو استُبعد عند التنفيذ).</param>
/// <param name="Protected">ظاهر ولن يُستبعد، بأسبابه في <paramref name="ProtectedByReason"/>.</param>
/// <param name="RemainingPending">العداد بعد التنفيذ (عند المعاينة: المتوقع بعد التنفيذ).</param>
public sealed record DiscardAllResult(bool Committed, int Eligible, int Protected,
    IReadOnlyDictionary<string, int> ProtectedByReason, IReadOnlyList<DiscardOutcome> ProtectedItems, string Token,
    int RemainingPending);

public sealed record QuickBatchSummary(Guid Id, string? Method, string? Audience, string? FileName, int RowCount,
    int Created, int Pending, int Duplicate, int Failed, string? Status, DateTimeOffset CreatedAt, string? CreatedByName);

public sealed record UndoResult(int Reversed, int Discarded, IReadOnlyList<UndoBlocked> Blocked, string Status);

public sealed record UndoBlocked(Guid PartyId, string Name, string Reason);

/// <param name="HeaderRow">رقم صف العناوين في الملف (يبدأ من 1).</param>
/// <param name="SourceRows">رقم كل صف بيانات في الملف الأصلي، بنفس ترتيب <paramref name="Rows"/>.</param>
public sealed record ExcelSheet(string Name, IReadOnlyList<string> Headers, IReadOnlyList<IReadOnlyList<string>> Rows,
    IReadOnlyDictionary<string, int> Mapping, int HeaderRow = 1, IReadOnlyList<int>? SourceRows = null);

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
    TimeProvider clock,
    IQuickEntryProbe probe)
{
    public const int MaxRows = 5000;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static readonly IReadOnlyDictionary<string, string[]> Columns = new Dictionary<string, string[]>
    {
        ["name"] = ["الاسم", "اسم", "اسم الشركه", "الشركه", "اسم العميل", "اسم المورد", "العميل", "المورد", "اسم المصنع",
            "name", "company", "company name", "customer", "supplier", "client"],
        ["phone"] = ["الهاتف", "هاتف", "رقم الهاتف", "التليفون", "تليفون", "الموبايل", "موبايل", "رقم الموبايل", "جوال",
            "واتساب", "رقم الواتساب", "phone", "mobile", "tel", "telephone", "whatsapp", "mobile number", "phone number"],
        ["material"] = ["الخامه", "خامه", "نوع الخامه", "الخامات", "material", "material type", "resin"],
        ["grade"] = ["grade", "الجريد", "جريد", "الدرجه", "grades", "grade code", "كود الجريد"],
        ["manufacturer"] = ["الشركه المصنعه", "الشركه المنتجه", "المصنع", "المنتج", "manufacturer", "maker", "producer",
            "brand"],
        ["origin"] = ["المنشا", "منشا", "بلد المنشا", "بلد الصنع", "الدوله", "origin", "country", "country of origin",
            "made in"],
        ["kind"] = ["النوع", "نوع", "نوع السجل", "التصنيف", "عميل او مورد", "عميل/مورد", "type", "role", "kind"],
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
        public required List<(Guid Id, string Code, string NameAr, string? NameEn)> Countries;
    }

    private async Task<Catalog> LoadCatalogAsync(CancellationToken ct)
    {
        var makers = await db.Manufacturers.AsNoTracking().ToDictionaryAsync(m => m.Id, m => m.Name, ct);
        var grades = (await db.Grades.AsNoTracking().Where(g => g.IsActive)
                .Select(g => new { g.Id, g.MaterialId, g.ManufacturerId, g.Code, g.NormalizedCode }).ToListAsync(ct))
            .Select(g => (g.Id, g.MaterialId, g.ManufacturerId, g.Code, g.NormalizedCode,
                g.ManufacturerId is { } m ? makers.GetValueOrDefault(m) : null))
            .ToList();
        var countries = (await db.LookupItems.AsNoTracking()
                .Where(l => l.Category == LookupCategories.Country && l.IsActive)
                .Select(l => new { l.Id, l.Code, l.NameAr, l.NameEn }).ToListAsync(ct))
            .Select(l => (l.Id, l.Code, l.NameAr, l.NameEn)).ToList();
        return new Catalog
        {
            Materials = await db.Materials.AsNoTracking().Include(m => m.Aliases).Where(m => m.IsActive).ToListAsync(ct),
            Grades = grades,
            MakerNames = makers,
            Countries = countries,
        };
    }

    /// <param name="Issues">العوائق فقط.</param>
    /// <param name="UnverifiedGrade">نص الـ Grade الذي سيُحفظ «غير موثق» (عند عدم وجود مطابقة مؤكدة).</param>
    private sealed record Resolved(string? Kind, string? Name, string? E164, Guid? MaterialId, Guid? GradeId,
        string? MaterialCode, string? GradeLabel, List<string> Issues, List<string> Warnings, string? UnverifiedGrade,
        string? UnverifiedManufacturer, Guid? OriginId)
    {
        public bool NeedsReview => Warnings.Any(QuickEntryIssues.Review.Contains);
    }

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
        var warnings = new List<string>();
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

        // الخامة إلزامية: من القائمة، أو من Grade اختاره المستخدم من الكتالوج، أو بالكود/الاسم البديل.
        var gradeText = string.IsNullOrWhiteSpace(row.Grade) ? null : row.Grade.Trim();
        var makerText = string.IsNullOrWhiteSpace(row.Manufacturer) ? null : row.Manufacturer.Trim();
        var picked = row.GradeId is { } gid ? catalog.Grades.FirstOrDefault(g => g.Id == gid) : default;
        var pickedValid = row.GradeId is not null && picked.Id != Guid.Empty;
        Material? material = null;
        if (row.MaterialId is { } mid)
            material = catalog.Materials.FirstOrDefault(m => m.Id == mid);
        else if (pickedValid)
            material = catalog.Materials.FirstOrDefault(m => m.Id == picked.MaterialId);
        else if (!string.IsNullOrWhiteSpace(row.Material))
        {
            var key = TextNormalizer.NormalizeCode(Synonyms.MaterialCode(TextNormalizer.Normalize(row.Material)) ?? row.Material);
            material = catalog.Materials.FirstOrDefault(m => TextNormalizer.NormalizeCode(m.Code) == key
                || m.Aliases.Any(a => a.Normalized == key));
        }
        if (material is null)
            issues.Add(row.MaterialId is null && string.IsNullOrWhiteSpace(row.Material) && !pickedValid
                ? QuickEntryIssues.MaterialMissing
                : QuickEntryIssues.MaterialUnknown);

        // الـ Grade اختياري: يُربط بالكتالوج فقط عند مطابقة وحيدة مؤكدة للخامة (والشركة إن كُتبت).
        // غير ذلك يُحفظ نصه «غير موثق» ولا يُنشأ أو يُعدّل أي Grade في الكتالوج.
        (Guid Id, Guid MaterialId, Guid? MakerId, string Code, string NormalizedCode, string? Maker)? grade = null;
        if (pickedValid)
        {
            if (material is not null && picked.MaterialId != material.Id)
            {
                warnings.Add(QuickEntryIssues.GradeMaterialMismatch);
                gradeText ??= picked.Code;
            }
            else
                grade = picked;
        }
        else if (material is null)
        {
            // تحذيرات الـ Grade تخص خامة معروفة؛ بدونها يكفي عائق الخامة (والنص يبقى محفوظًا).
        }
        else if (row.GradeId is not null)
        {
            // Grade اختير من القائمة ثم لم يعد موجودًا: لا ربط، والنص (إن وُجد) غير موثق.
            warnings.Add(gradeText is null ? QuickEntryIssues.GradeMissing : QuickEntryIssues.GradeUnverified);
        }
        else if (gradeText is null)
            warnings.Add(QuickEntryIssues.GradeMissing);
        else
        {
            var code = TextNormalizer.NormalizeCode(gradeText);
            var sameMaterial = catalog.Grades.Where(g => g.MaterialId == material.Id && g.NormalizedCode == code).ToList();
            var candidates = sameMaterial;
            if (makerText is not null && sameMaterial.Count > 0)
            {
                var variants = Synonyms.MakerVariants(TextNormalizer.Normalize(makerText));
                candidates = sameMaterial.Where(g => g.Maker is not null
                    && variants.Contains(TextNormalizer.Normalize(g.Maker))).ToList();
            }
            if (candidates.Count == 1)
                grade = candidates[0];
            else if (candidates.Count > 1)
                warnings.Add(QuickEntryIssues.GradeAmbiguous);
            else if (sameMaterial.Count > 0)
                warnings.Add(QuickEntryIssues.GradeManufacturerMismatch);
            else if (code.Length > 0 && catalog.Grades.Any(g => g.NormalizedCode == code))
                warnings.Add(QuickEntryIssues.GradeMaterialMismatch);
            else
                warnings.Add(QuickEntryIssues.GradeUnverified);
        }

        // بلد المنشأ اختياري: يُربط فقط بمطابقة وحيدة بالاسم أو الكود، وإلا يبقى نصه في صف الإدخال.
        Guid? originId = null;
        if (!string.IsNullOrWhiteSpace(row.Origin))
        {
            var key = TextNormalizer.Normalize(row.Origin);
            var matches = catalog.Countries.Where(c => TextNormalizer.Normalize(c.NameAr) == key
                || TextNormalizer.Normalize(c.Code) == key
                || (c.NameEn is not null && TextNormalizer.Normalize(c.NameEn) == key)).ToList();
            if (matches.Count == 1)
                originId = matches[0].Id;
            else
                warnings.Add(QuickEntryIssues.OriginUnknown);
        }

        var unverified = grade is null ? gradeText : null;
        var label = grade is { } gr
            ? gr.Maker is null ? gr.Code : $"{gr.Code} — {gr.Maker}"
            : unverified is null ? null : $"{unverified} (غير موثق)";
        return new Resolved(kind, name.Length == 0 ? null : name, e164, material?.Id, grade?.Id, material?.Code, label,
            issues, warnings, unverified, grade is null ? makerText : null, originId);
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
                // إعادة إرسال نفس الدفعة (انقطاع اتصال أو ضغط مزدوج): تُستكمل الصفوف الجاهزة التي لم تنتهِ
                // محاولة إنشائها، ثم تُعاد النتيجة المحفوظة دون أي تكرار.
                if (existing.CreatedBy != user.UserId || existing.Method is null)
                    return AppError.Conflict("quick.id_taken", "معرف الدفعة مستخدم بالفعل");
                await ResumeAsync(existing.Id, ct);
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
                    res.GradeLabel, null, dupId, dupName, note, res.Warnings, res.UnverifiedGrade,
                    res.NeedsReview && !row.ReviewAcknowledged);

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
            // Grade ملتبس لم يؤكده المستخدم: لا تُنشأ بطاقته حتى المراجعة الصريحة.
            results.Add(res.NeedsReview && !row.ReviewAcknowledged
                ? Result(QuickRowStatus.NeedsReview, "Grade يحتاج مراجعة وتأكيدًا قبل الحفظ")
                : Result(QuickRowStatus.Ready));
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
        foreach (var (row, res) in resolved)
        {
            var r = results.First(x => x.Id == row.Id);
            var ready = r.Status == QuickRowStatus.Ready;
            db.ImportEntries.Add(new ImportEntry
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
                OriginText = Cut(row.Origin, 100),
                MaterialId = res.MaterialId,
                GradeId = res.GradeId,
                ReviewAcknowledged = row.ReviewAcknowledged && res.NeedsReview,
                // الجاهز يُحفظ أولًا «بانتظار الإنشاء» حتى تنتهي محاولة إنشاء بطاقته (قابل للاستكمال).
                AwaitingPromotion = ready,
                Status = ready || r.Status == QuickRowStatus.NeedsReview ? ImportEntryStatus.Pending : r.Status,
                DuplicateOfId = r.DuplicateOfId,
                Note = ready ? null : Cut(r.Note, 500),
                CreatedBy = user.UserId,
                CreatedAt = now,
                UpdatedBy = user.UserId,
                UpdatedAt = now,
            });
        }
        db.Audit(user, clock, "quick.batch", "import", batch.Id,
            new { request.Method, request.Audience, rows = request.Rows.Count });
        await db.SaveChangesAsync(ct);

        // الصفوف الجاهزة: نفس خدمة التسجيل (صلاحيات، تكرار، اسم مشابه، تدقيق، المنشئ من الجلسة).
        await ResumeAsync(batch.Id, ct);
        // عدادات الدفعة دائمًا، حتى لو لم يكن فيها صف جاهز.
        await RecountAsync(batch, ct);
        return await BatchResultAsync(batch, ct);
    }

    /// <summary>
    /// ينشئ بطاقات الصفوف التي حُفظت جاهزة ولم تنتهِ محاولة إنشائها (أول تنفيذ، أو إعادة إرسال بعد انقطاع).
    /// البطاقة بمعرف الصف نفسه: إن كانت أُنشئت قبل الانقطاع تُعاد نفسها ويُكمل الصف، فلا تتكرر أبدًا.
    /// </summary>
    private async Task ResumeAsync(Guid batchId, CancellationToken ct)
    {
        var batch = await db.ImportBatches.FirstAsync(b => b.Id == batchId, ct);
        var waiting = await db.ImportEntries.Where(e => e.BatchId == batchId && e.AwaitingPromotion)
            .OrderBy(e => e.RowNumber).ToListAsync(ct);
        if (waiting.Count == 0)
            return;
        var catalog = await LoadCatalogAsync(ct);
        foreach (var entry in waiting)
        {
            var res = Resolve(ToRow(entry), entry.Kind ?? batch.Audience ?? QuickEntryAudience.Mixed, catalog);
            if (entry.Status != ImportEntryStatus.Pending || res.Issues.Count > 0 || (res.NeedsReview && !entry.ReviewAcknowledged))
            {
                // تغيرت حالته أو الكتالوج منذ الحفظ: يبقى كما هو للاستكمال اليدوي.
                entry.AwaitingPromotion = false;
                await SaveOrReloadAsync(entry, ct);
                continue;
            }
            await PromoteAsync(entry, res, confirmSimilar: false, ct);
        }
        await RecountAsync(batch, ct);
    }

    private static string? Cut(string? value, int max) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().Length > max ? value.Trim()[..max] : value.Trim();

    /// <summary>
    /// إنشاء السجل بمعرف الصف؛ إعادة المحاولة تعيد نفس السجل (لا تكرار). الـ Grade اختياري ونصه غير الموثق
    /// يُحفظ على الخامة. أي نتيجة تُنهي علامة «بانتظار الإنشاء»؛ الانقطاع قبل الحفظ يتركها للاستكمال.
    /// </summary>
    private async Task<AppError?> PromoteAsync(ImportEntry entry, Resolved res, bool confirmSimilar, CancellationToken ct)
    {
        // الصف محجوز للإنشاء (awaiting_promotion) قبل هذه النقطة: الاستبعاد المتزامن يرفضه.
        await probe.AfterPromotionClaimAsync(entry.Id, ct);
        var customer = res.Kind == QuickEntryAudience.Customers;
        var materialId = res.MaterialId!.Value;
        Result<CreatePartyResult> created;
        try
        {
            created = await parties.CreateForQuickEntryAsync(new CreatePartyRequest(entry.Id, res.Name!, customer, !customer,
                    [new PhoneInput(res.E164!)],
                    Interests: customer ? [new InterestInput(materialId, GradeId: res.GradeId, OriginCountryId: res.OriginId)] : null,
                    Products: customer ? null : [new ProductInput(materialId, GradeId: res.GradeId, OriginCountryId: res.OriginId)],
                    ConfirmSimilar: confirmSimilar),
                new UnverifiedSpec(res.UnverifiedGrade, res.UnverifiedManufacturer), ct);
        }
        catch (DbUpdateException)
        {
            // تعارض كتابة متزامن (مثل إنشاء بطاقة بنفس المعرف في طلب آخر). لا تكرار بفضل المفتاح الأساسي؛
            // يُفك الحجز فقط إن لم تُنشأ البطاقة، والطلب يُعاد لاحقًا فيعيد نفس البطاقة.
            if (!await db.Parties.AnyAsync(p => p.Id == entry.Id, ct))
                await db.ImportEntries.Where(x => x.Id == entry.Id && x.AwaitingPromotion)
                    .ExecuteUpdateAsync(u => u.SetProperty(x => x.AwaitingPromotion, false), ct);
            return AppError.Conflict("quick.in_progress", "تعذر الحفظ بسبب عملية متزامنة. أعد المحاولة");
        }

        var now = clock.GetUtcNow();
        entry.UpdatedAt = now;
        entry.UpdatedBy = user.UserId;
        entry.MaterialId = res.MaterialId;
        entry.GradeId = res.GradeId;
        entry.AwaitingPromotion = false;
        entry.ErrorCode = null;
        if (created.IsSuccess)
        {
            entry.Status = ImportEntryStatus.Completed;
            entry.PartyId = created.Value!.Id;
            // البطاقة بمعرف الصف: أنشأها هذا الصف حتى لو أُنشئت في محاولة سابقة انقطعت قبل تحديثه.
            entry.CreatedParty = created.Value.Id == entry.Id;
            entry.DuplicateOfId = null;
            entry.Note = null;
            // مشروط بالحالة والحجز كما قُرئا؛ إن أكمله طلب متزامن آخر فالنتيجة نفسها (لا تكرار).
            return await SaveOrReloadAsync(entry, ct) || entry.Status == ImportEntryStatus.Completed
                ? null
                : Changed(entry);
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
                // خطأ معالجة غير متوقع (ليس نقصًا ولا تحذيرًا): يبقى للاستكمال اليدوي مع كوده للتشخيص.
                entry.Status = ImportEntryStatus.Pending;
                entry.ErrorCode = Cut(error.Code, 64);
                entry.Note = Cut(error.Message, 500);
                break;
        }
        await SaveOrReloadAsync(entry, ct);
        return error;
    }

    /// <summary>عدادات الدفعة من حالات صفوفها في قاعدة البيانات (بقفل صف الدفعة).</summary>
    private Task RecountAsync(ImportBatch batch, CancellationToken ct) => db.RecountImportBatchesAsync([batch.Id], ct);

    /// <summary>
    /// يحفظ تعديل صف بشرط أن حالته وحجزه لم يتغيرا منذ قراءته (تعارض متزامن). عند التعارض يعيد قراءة الصف
    /// بقيمه الحالية ويعيد false.
    /// </summary>
    private async Task<bool> SaveOrReloadAsync(ImportEntry entry, CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
            return true;
        }
        catch (DbUpdateConcurrencyException)
        {
            await db.ReloadAsync(entry, ct);
            return false;
        }
    }

    /// <summary>خطأ يصف حالة الصف بعد تعارض متزامن.</summary>
    private static AppError Changed(ImportEntry e) => e.Status switch
    {
        ImportEntryStatus.Discarded => AppError.Conflict("quick.closed", "هذا الصف استُبعد"),
        ImportEntryStatus.Completed => AppError.Conflict("quick.closed", "هذا الصف أصبح بطاقة بالفعل"),
        _ when e.AwaitingPromotion => AppError.Conflict("quick.in_progress", "جارٍ إنشاء بطاقة هذا الصف. أعد المحاولة بعد قليل"),
        _ => AppError.Conflict("quick.changed", "تغير هذا الصف للتو. أعد تحميل القائمة"),
    };

    /// <summary>
    /// يحجز الصف للإنشاء أو الدمج قبل أي تعديل على بطاقات العملاء/الموردين: تحديث مشروط بأن الصف ما زال
    /// بنفس حالته وغير محجوز. الاستبعاد يشترط عدم الحجز، فلا يجتمع الإنشاء والاستبعاد أبدًا.
    /// </summary>
    private async Task<AppError?> ClaimAsync(ImportEntry e, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        if (e.AwaitingPromotion)
        {
            // محجوز لطلب آخر جارٍ: لا يُنفذ إنشاءان معًا. الحجز القديم (طلب انقطع) يُستكمل؛ البطاقة بمعرف
            // الصف فلا تتكرر.
            if (e.UpdatedAt > now - StaleClaim)
                return Changed(e);
            e.Touch(user.UserId, now);
            return await SaveOrReloadAsync(e, ct) ? null : Changed(e);
        }
        e.AwaitingPromotion = true;
        e.Touch(user.UserId, now);
        return await SaveOrReloadAsync(e, ct) ? null : Changed(e);
    }

    /// <summary>بعدها يُعتبر حجز الإنشاء متروكًا (طلب انقطع) ويمكن استكماله.</summary>
    private static readonly TimeSpan StaleClaim = TimeSpan.FromMinutes(2);

    private async Task<QuickBatchResult> BatchResultAsync(ImportBatch batch, CancellationToken ct)
    {
        var catalog = await LoadCatalogAsync(ct);
        var entries = await db.ImportEntries.AsNoTracking().Where(e => e.BatchId == batch.Id)
            .OrderBy(e => e.RowNumber).ToListAsync(ct);
        var names = await DuplicateNamesAsync(entries, ct);
        var rows = entries.Select(e =>
        {
            var res = Resolve(ToRow(e), e.Kind ?? batch.Audience ?? QuickEntryAudience.Mixed, catalog);
            var done = e.Status == ImportEntryStatus.Completed;
            return new QuickRowResult(e.Id, e.RowNumber, e.Status, e.Kind, done ? [] : res.Issues,
                e.MaterialId ?? res.MaterialId, e.GradeId ?? res.GradeId, res.MaterialCode, res.GradeLabel, e.PartyId,
                e.DuplicateOfId, e.DuplicateOfId is { } d ? names.GetValueOrDefault(d) : null, e.Note,
                res.Warnings, res.UnverifiedGrade, !done && res.NeedsReview && !e.ReviewAcknowledged, e.ErrorCode);
        }).ToList();
        return Summarize(batch.Id, true, rows);
    }

    private static QuickBatchResult Summarize(Guid id, bool committed, List<QuickRowResult> rows) => new(id, committed,
        rows.Count,
        rows.Count(r => r.Status is ImportEntryStatus.Completed or QuickRowStatus.Ready),
        rows.Count(r => r.Status is ImportEntryStatus.Pending or QuickRowStatus.NeedsReview),
        rows.Count(r => r.Status == ImportEntryStatus.Duplicate),
        rows.Count(r => r.Status == ImportEntryStatus.Failed), rows);

    private static QuickEntryRow ToRow(ImportEntry e) => new(e.Id, e.RowNumber, e.Kind, e.Name, e.Phone, e.MaterialText,
        e.GradeText, e.ManufacturerText, e.MaterialId, e.GradeId, e.OriginText, e.ReviewAcknowledged);

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
                users.GetValueOrDefault(e.CreatedBy), e.OriginText, res.Warnings, res.UnverifiedGrade,
                e.Status != ImportEntryStatus.Completed && res.NeedsReview && !e.ReviewAcknowledged, e.ReviewAcknowledged,
                e.ErrorCode);
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
        var specChanged = e.MaterialText != Cut(update.Material, 100) || e.GradeText != Cut(update.Grade, 100)
            || e.ManufacturerText != Cut(update.Manufacturer, 120) || e.MaterialId != update.MaterialId
            || e.GradeId != update.GradeId;
        e.Name = Cut(update.Name, 200);
        e.Phone = Cut(update.Phone, 40);
        e.MaterialText = Cut(update.Material, 100);
        e.GradeText = Cut(update.Grade, 100);
        e.ManufacturerText = Cut(update.Manufacturer, 120);
        // نسخة 0.6.0 لا ترسل المنشأ: غيابه يبقيه كما هو، والنص الفارغ يمسحه.
        if (update.Origin is not null)
            e.OriginText = Cut(update.Origin, 100);
        e.MaterialId = update.MaterialId;
        e.GradeId = update.GradeId;
        // تأكيد المراجعة يخص الخامة والـ Grade كما كانا: تغييرهما يلغيه ما لم يُرسل تأكيد جديد.
        e.ReviewAcknowledged = update.ReviewAcknowledged ?? (e.ReviewAcknowledged && !specChanged);
        e.ErrorCode = null;
        if (e.Status is ImportEntryStatus.Failed)
            e.Status = ImportEntryStatus.Pending;
        if (e.AwaitingPromotion)
            return Changed(e);
        e.Touch(user.UserId, clock.GetUtcNow());
        if (!await SaveOrReloadAsync(e, ct))
            return Changed(e);
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
        var review = ReviewGate(e, res, request.AcknowledgeReview);
        if (review is not null)
            return review;
        e.Kind = res.Kind;
        if (await ClaimAsync(e, ct) is { } claimError)
            return e.Status == ImportEntryStatus.Completed && e.PartyId is { } finished
                ? new CompletedEntry(e.Id, finished, e.CreatedParty)
                : claimError;
        var error = await PromoteAsync(e, res, request.ConfirmSimilar, ct);
        await db.RecountImportBatchesAsync([e.BatchId], ct);
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
        var review = ReviewGate(e, res, request.AcknowledgeReview);
        if (review is not null)
            return review;

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
        }
        // حجز الصف قبل أي إضافة للسجل الموجود (لا يُستبعد أثناء الدمج ولا يُدمج بعد استبعاده).
        if (await ClaimAsync(e, ct) is { } claimError)
            return e.Status == ImportEntryStatus.Completed && e.PartyId is { } finished
                ? new CompletedEntry(e.Id, finished, e.CreatedParty)
                : claimError;
        await probe.AfterPromotionClaimAsync(e.Id, ct);
        async Task<AppError> Release(AppError error)
        {
            e.AwaitingPromotion = false;
            await SaveOrReloadAsync(e, ct);
            return error;
        }
        if (customer ? !party.IsCustomer : !party.IsSupplier)
        {
            var role = await parties.AddRoleAsync(party.Id, new AddRoleRequest(customer, !customer), ct);
            if (!role.IsSuccess)
                return await Release(role.Error!);
        }
        var unverified = new UnverifiedSpec(res.UnverifiedGrade, res.UnverifiedManufacturer);
        if (customer)
        {
            var added = await parties.AddInterestForQuickEntryAsync(party.Id,
                new InterestInput(res.MaterialId!.Value, GradeId: res.GradeId, OriginCountryId: res.OriginId), unverified, ct);
            if (!added.IsSuccess)
                return await Release(added.Error!);
        }
        else
        {
            var added = await parties.AddProductForQuickEntryAsync(party.Id,
                new ProductInput(res.MaterialId!.Value, GradeId: res.GradeId, OriginCountryId: res.OriginId), unverified, ct);
            if (!added.IsSuccess)
                return await Release(added.Error!);
        }

        e.Status = ImportEntryStatus.Completed;
        e.PartyId = party.Id;
        e.CreatedParty = false;
        e.AwaitingPromotion = false;
        e.ErrorCode = null;
        e.Kind = res.Kind;
        e.Note = "أُضيفت الخامة لسجل موجود";
        e.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "quick.merged", "party", party.Id, new { entry = e.Id, batch = e.BatchId });
        if (!await SaveOrReloadAsync(e, ct) && e.Status != ImportEntryStatus.Completed)
            return Changed(e);
        await db.RecountImportBatchesAsync([e.BatchId], ct);
        return new CompletedEntry(e.Id, party.Id, false);
    }

    /// <summary>
    /// Grade ملتبس (لشركتين، أو لخامة أخرى، أو لشركة غير المكتوبة) يُحفظ نصًا غير موثق فقط بعد تأكيد صريح،
    /// ولا يُنشأ أي ربط بالكتالوج. التأكيد يُحفظ على الصف ويُسجل في التدقيق.
    /// </summary>
    private AppError? ReviewGate(ImportEntry e, Resolved res, bool acknowledge)
    {
        if (!res.NeedsReview || e.ReviewAcknowledged)
            return null;
        if (!acknowledge)
            return new AppError(ErrorKind.Conflict, "quick.review_required",
                "الـ Grade يحتاج مراجعة: سيُحفظ كنص غير موثق دون ربطه بالكتالوج. أكد للمتابعة",
                res.Warnings.Where(QuickEntryIssues.Review.Contains).ToList());
        e.ReviewAcknowledged = true;
        db.Audit(user, clock, "quick.review_acknowledged", "import", e.Id,
            new { batch = e.BatchId, warnings = res.Warnings, grade = res.UnverifiedGrade });
        return null;
    }

    // ---------------- تنظيف «بانتظار الاستكمال» (استبعاد منطقي) ----------------

    /// <summary>
    /// سبب حماية الصف من الاستبعاد، أو null إن كان مؤهلًا. الاستبعاد منطقي (الحالة discarded) ويخص صفوف
    /// الإدخال المؤقتة فقط: لا يلمس بطاقات العملاء/الموردين ولا الكتالوج ولا سجل التدقيق.
    /// </summary>
    private static string? Protection(ImportEntry e, bool partyWithSameId) =>
        e.Status == ImportEntryStatus.Completed ? DiscardReasons.Completed
        : e.PartyId is not null ? DiscardReasons.LinkedParty
        : e.AwaitingPromotion ? DiscardReasons.AwaitingPromotion
        : partyWithSameId ? DiscardReasons.UncertainPromotion
        : null;

    private async Task<HashSet<Guid>> PartiesWithSameIdAsync(IEnumerable<Guid> ids, CancellationToken ct)
    {
        var list = ids.ToList();
        return list.Count == 0
            ? []
            : (await db.Parties.AsNoTracking().Where(p => list.Contains(p.Id)).Select(p => p.Id).ToListAsync(ct)).ToHashSet();
    }

    /// <summary>
    /// داخل معاملة مفتوحة وبعد قفل الصفوف: يستبعدها ويسجل التدقيق ثم يعيد حساب عدادات دفعاتها. التحديث
    /// مشروط أيضًا بالحالة والحجز كما قُرئا (رمز التزامن)؛ أي تعارض يعيد false وتُلغى المعاملة.
    /// </summary>
    private async Task<bool> ApplyDiscardAsync(List<ImportEntry> entries, string action, object audit, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        foreach (var e in entries)
        {
            e.Status = ImportEntryStatus.Discarded;
            e.Touch(user.UserId, now);
        }
        db.Audit(user, clock, action, "import", entries.Count == 1 ? entries[0].Id : Guid.Empty, audit);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return false;
        }
        await db.RecountImportBatchesAsync(entries.Select(e => e.BatchId).ToList(), ct);
        return true;
    }

    private async Task<int> RemainingPendingAsync(CancellationToken ct) =>
        await VisibleEntries().CountAsync(e => e.Status == ImportEntryStatus.Pending || e.Status == ImportEntryStatus.Duplicate, ct);

    /// <summary>
    /// استبعاد صف (يبقى في سجل الدفعة ولا يُحذف). الصف يُقفل ويُعاد فحصه بقيمه الحالية داخل المعاملة، فلا
    /// يتداخل مع إنشاء بطاقته. المستبعد سابقًا نتيجة ناجحة (تكرار الطلب آمن)؛ المكتمل أو المرتبط ببطاقة أو
    /// الذي لم تنتهِ محاولة إنشائه محمي.
    /// </summary>
    public async Task<Result<DiscardOutcome>> DiscardAsync(Guid id, CancellationToken ct)
    {
        var loaded = await LoadEditableEntryAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var e = loaded.Value!;
        await using var tx = await db.BeginTransactionAsync(ct);
        await db.LockImportEntriesAsync([e.Id], ct);
        await db.ReloadAsync(e, ct);
        if (e.Status == ImportEntryStatus.Discarded)
            return new DiscardOutcome(e.Id, "already_discarded");
        var reason = Protection(e, (await PartiesWithSameIdAsync([e.Id], ct)).Contains(e.Id));
        if (reason == DiscardReasons.Completed)
            return AppError.Conflict("quick.closed", "هذا الصف أصبح بطاقة بالفعل");
        if (reason is not null)
            return new AppError(ErrorKind.Conflict, "quick.protected",
                "لا يمكن استبعاد هذا الصف: مرتبط ببطاقة أو لم تنتهِ محاولة إنشائها. أعد إرسال الدفعة أو راجع الإدارة",
                reason);
        await probe.BeforeDiscardMutationAsync([e.Id], ct);
        if (!await ApplyDiscardAsync([e], "quick.discarded", new { entry = e.Id, batch = e.BatchId }, ct))
            return AppError.Conflict("quick.changed", "تغير هذا الصف للتو. أعد تحميل القائمة");
        await tx.CommitAsync(ct);
        return new DiscardOutcome(e.Id, "discarded");
    }

    public const int MaxDiscardIds = 500;

    /// <summary>
    /// استبعاد مجموعة محددة (حتى 500). الصلاحية لكل صف؛ غير الظاهر يُعامل «غير موجود» دون كشفه، والمحمي
    /// يُتخطى بسببه. الصفوف تُقفل وتُفحص بقيمها الحالية، والمؤهل كله يُستبعد في معاملة واحدة.
    /// </summary>
    public async Task<Result<DiscardManyResult>> DiscardManyAsync(DiscardManyRequest request, CancellationToken ct)
    {
        if (!CanUse)
            return AppError.Forbidden();
        var ids = (request.Ids ?? []).Where(i => i != Guid.Empty).Distinct().ToList();
        if (ids.Count is 0 or > MaxDiscardIds)
            return AppError.Validation($"حدد من 1 إلى {MaxDiscardIds} صف", "quick.discard_ids");

        var visible = await VisibleEntries().AsNoTracking().Where(e => ids.Contains(e.Id)).Select(e => e.Id).ToListAsync(ct);
        var skipped = ids.Except(visible).Select(id => new DiscardOutcome(id, "skipped", DiscardReasons.NotFound)).ToList();
        var already = 0;
        var targets = new List<ImportEntry>();
        await using (var tx = await db.BeginTransactionAsync(ct))
        {
            var locked = await db.LockImportEntriesAsync(visible, ct);
            var parties = await PartiesWithSameIdAsync(locked.Select(e => e.Id), ct);
            foreach (var e in locked.OrderBy(e => ids.IndexOf(e.Id)))
            {
                if (!CanEditEntry(e))
                    skipped.Add(new DiscardOutcome(e.Id, "skipped", DiscardReasons.Forbidden));
                else if (e.Status == ImportEntryStatus.Discarded)
                    already++;
                else if (Protection(e, parties.Contains(e.Id)) is { } reason)
                    skipped.Add(new DiscardOutcome(e.Id, "skipped", reason));
                else
                    targets.Add(e);
            }
            if (targets.Count > 0)
            {
                await probe.BeforeDiscardMutationAsync(targets.Select(e => e.Id).ToList(), ct);
                if (!await ApplyDiscardAsync(targets, "quick.discard_bulk",
                        new { rows = targets.Count, entries = targets.Select(e => e.Id) }, ct))
                    return AppError.Conflict("quick.changed", "تغيرت بعض الصفوف للتو. أعد المحاولة");
            }
            await tx.CommitAsync(ct);
        }
        return new DiscardManyResult(targets.Count, already, skipped, await RemainingPendingAsync(ct));
    }

    /// <summary>
    /// حذف كل المؤهل من «بانتظار الاستكمال» الظاهر للمستخدم (معلق ومكرر)، بفلتر اختياري للنوع أو الدفعة.
    /// المعاينة لا تكتب شيئًا وتعيد رمز لقطة لمجموعة المؤهل. التنفيذ يقفل صفوف النطاق فقط ويعيد حساب المؤهل
    /// والرمز بقيمها الحالية داخل نفس المعاملة: أي اختلاف عن المعاينة يُرفض دون أي استبعاد.
    /// </summary>
    public async Task<Result<DiscardAllResult>> DiscardAllAsync(DiscardAllRequest request, CancellationToken ct)
    {
        if (!CanUse)
            return AppError.Forbidden();
        if (!request.Preview && string.IsNullOrWhiteSpace(request.Token))
            return AppError.Validation("المعاينة مطلوبة قبل الحذف", "quick.preview_required");

        IQueryable<ImportEntry> Scope()
        {
            var query = VisibleEntries().Where(e => e.Status == ImportEntryStatus.Pending || e.Status == ImportEntryStatus.Duplicate);
            if (request.Kind is { Length: > 0 } kind)
                query = kind == "none" ? query.Where(e => e.Kind == null) : query.Where(e => e.Kind == kind);
            if (request.BatchId is { } batchId)
                query = query.Where(e => e.BatchId == batchId);
            return query;
        }

        async Task<(List<ImportEntry> Eligible, List<DiscardOutcome> Protected, string Token)> EvaluateAsync(
            List<ImportEntry> entries)
        {
            var parties = await PartiesWithSameIdAsync(entries.Select(e => e.Id), ct);
            var eligible = new List<ImportEntry>();
            var protectedItems = new List<DiscardOutcome>();
            foreach (var e in entries.OrderBy(e => e.Id))
            {
                var reason = !CanEditEntry(e) ? DiscardReasons.Forbidden : Protection(e, parties.Contains(e.Id));
                if (reason is null)
                    eligible.Add(e);
                else
                    protectedItems.Add(new DiscardOutcome(e.Id, "skipped", reason));
            }
            return (eligible, protectedItems, SnapshotToken(eligible));
        }

        static Dictionary<string, int> ByReason(List<DiscardOutcome> items) =>
            items.GroupBy(p => p.Reason!).ToDictionary(g => g.Key, g => g.Count());

        if (request.Preview)
        {
            var (eligible, protectedItems, token) = await EvaluateAsync(await Scope().AsNoTracking().ToListAsync(ct));
            var visibleTotal = await RemainingPendingAsync(ct);
            return new DiscardAllResult(false, eligible.Count, protectedItems.Count, ByReason(protectedItems), protectedItems,
                token, visibleTotal - eligible.Count);
        }

        DiscardAllResult result;
        await using (var tx = await db.BeginTransactionAsync(ct))
        {
            // قفل صفوف النطاق فقط (لا قفل عام)، ثم إعادة قراءة النطاق بعد القفل: الحالات لا تتغير حتى الاعتماد.
            var candidates = await Scope().AsNoTracking().Select(e => e.Id).ToListAsync(ct);
            var locked = await db.LockImportEntriesAsync(candidates, ct);
            var stillInScope = (await Scope().AsNoTracking().Where(e => candidates.Contains(e.Id)).Select(e => e.Id)
                .ToListAsync(ct)).ToHashSet();
            var (eligible, protectedItems, token) = await EvaluateAsync(locked.Where(e => stillInScope.Contains(e.Id)).ToList());
            if (!string.Equals(request.Token, token, StringComparison.Ordinal))
                return AppError.Conflict("quick.snapshot_changed", "تغيرت القائمة منذ المعاينة. راجع الأعداد من جديد");
            if (eligible.Count > 0)
            {
                await probe.BeforeDiscardMutationAsync(eligible.Select(e => e.Id).ToList(), ct);
                if (!await ApplyDiscardAsync(eligible, "quick.discard_all",
                        new { rows = eligible.Count, protectedRows = protectedItems.Count, request.Kind, request.BatchId }, ct))
                    return AppError.Conflict("quick.snapshot_changed", "تغيرت القائمة منذ المعاينة. راجع الأعداد من جديد");
            }
            await tx.CommitAsync(ct);
            result = new DiscardAllResult(true, eligible.Count, protectedItems.Count, ByReason(protectedItems), protectedItems,
                token, 0);
        }
        return result with { RemainingPending = await RemainingPendingAsync(ct) };
    }

    /// <summary>بصمة مجموعة المؤهل (المعرفات وآخر تعديل لكل صف): أي إضافة أو تعديل بعد المعاينة يغيرها.</summary>
    private static string SnapshotToken(IEnumerable<ImportEntry> eligible)
    {
        var text = string.Join(";", eligible.OrderBy(e => e.Id).Select(e => $"{e.Id:N}:{e.UpdatedAt.UtcTicks}"));
        return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text)))[..32];
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
            string.Join("، ", d.Issues.Concat(d.Warnings ?? []).Select(IssueLabel)), d.Note, d.CreatedByName,
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
        QuickEntryIssues.GradeMissing => "بدون Grade",
        QuickEntryIssues.GradeUnknown => "Grade غير موجود لهذه الخامة",
        QuickEntryIssues.GradeAmbiguous => "Grade مسجل لأكثر من شركة — حدده",
        QuickEntryIssues.KindMissing => "نوع السجل (عميل/مورد)",
        QuickEntryIssues.GradeUnverified => "Grade غير موثق (غير موجود في الكتالوج)",
        QuickEntryIssues.GradeMaterialMismatch => "Grade مسجل لخامة أخرى — يحتاج مراجعة",
        QuickEntryIssues.GradeManufacturerMismatch => "Grade لا يطابق الشركة المصنعة — يحتاج مراجعة",
        QuickEntryIssues.OriginUnknown => "بلد المنشأ غير موجود في القائمة",
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
            if (e.Status is ImportEntryStatus.Pending or ImportEntryStatus.Duplicate or ImportEntryStatus.Failed
                && !e.AwaitingPromotion)
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
        List<(string Name, List<(int Row, string[] Cells)> Rows)> sheets;
        try
        {
            sheets = XlsxReader.ReadNumberedSheets(buffer);
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
            // صف العناوين: أول صف تتعرف فيه على حقلين على الأقل ضمن أول 10 صفوف (عناوين الملف فوقه
            // تُتجاوز)، وإلا الصف الأول كما كان.
            var headerIndex = 0;
            for (var i = 0; i < Math.Min(10, rows.Count); i++)
            {
                if (SuggestMapping(rows[i].Cells).Count >= 2)
                {
                    headerIndex = i;
                    break;
                }
            }
            var dataRows = rows.Skip(headerIndex + 1).Where(r => r.Cells.Any(c => c.Length > 0)).ToList();
            if (dataRows.Count > MaxRows)
                return AppError.Validation($"الحد الأقصى {MaxRows} صف في الورقة الواحدة", "import.too_many_rows");
            var headers = rows[headerIndex].Cells.Select(h => h.Trim()).ToList();
            var width = Math.Max(headers.Count, dataRows.Count == 0 ? 0 : dataRows.Max(r => r.Cells.Length));
            while (headers.Count < width)
                headers.Add("");
            var data = dataRows
                .Select(r => (IReadOnlyList<string>)Enumerable.Range(0, width).Select(i => i < r.Cells.Length ? r.Cells[i] : "").ToList())
                .ToList();
            result.Add(new ExcelSheet(name, headers, data, SuggestMapping(headers), rows[headerIndex].Row,
                dataRows.Select(r => r.Row).ToList()));
        }
        if (result.Count == 0)
            return AppError.Validation("الملف لا يحتوي على بيانات", "import.empty");
        return result;
    }

    /// <summary>
    /// تعيين مقترح بأسماء الأعمدة فقط: التطابق التام أقوى من الاحتواء، والاحتواء الأطول أقوى؛ يُوزَّع
    /// الأقوى أولًا ولا يُستخدم عمود لحقلين، فلا «يسرق» حقل عمود حقل آخر (مثل «الشركة» داخل
    /// «الشركة المصنعة»).
    /// </summary>
    public static Dictionary<string, int> SuggestMapping(IReadOnlyList<string> headers)
    {
        var normalized = headers.Select(TextNormalizer.Normalize).ToList();
        var candidates = new List<(string Field, int Column, int Score)>();
        foreach (var (field, names) in Columns)
        {
            var keys = names.Select(TextNormalizer.Normalize).ToList();
            for (var i = 0; i < normalized.Count; i++)
            {
                var h = normalized[i];
                if (h.Length == 0)
                    continue;
                if (keys.Contains(h))
                    candidates.Add((field, i, 1000 + h.Length));
                else if (keys.Where(k => k.Length >= 4 && h.Contains(k, StringComparison.Ordinal)).Select(k => k.Length)
                             .DefaultIfEmpty(0).Max() is var len and > 0)
                    candidates.Add((field, i, len));
            }
        }
        var map = new Dictionary<string, int>();
        foreach (var c in candidates.OrderByDescending(c => c.Score).ThenBy(c => c.Column))
        {
            if (map.ContainsKey(c.Field) || map.ContainsValue(c.Column))
                continue;
            map[c.Field] = c.Column;
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
                    .Select(i => new { i.PartyId, i.MaterialId, i.GradeId, i.OpenSpec, i.UnverifiedGrade, i.UnverifiedManufacturer })
                    .ToListAsync(ct)
                : await db.SupplierProducts.AsNoTracking().Where(p => ids.Contains(p.PartyId) && p.IsActive)
                    .Select(p => new { p.PartyId, p.MaterialId, p.GradeId, OpenSpec = false, p.UnverifiedGrade, p.UnverifiedManufacturer })
                    .ToListAsync(ct);
            // فلتر الـ Grade يطابق Grades الكتالوج فقط؛ الـ Grade غير الموثق لا يُعامل كمطابقة له.
            var bySpec = specs
                .Where(s => request.MaterialId is null || s.MaterialId == request.MaterialId)
                .Where(s => request.GradeId is null || s.GradeId == request.GradeId)
                .GroupBy(s => s.PartyId).ToDictionary(x => x.Key,
                    x => x.DistinctBy(s => (s.MaterialId, s.GradeId, s.UnverifiedGrade)).ToList());
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
                            gr?.Code ?? (s.OpenSpec ? "أي Grade" : UnverifiedLabel(s.UnverifiedGrade)),
                            gr?.Maker ?? UnverifiedLabel(s.UnverifiedManufacturer)));
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

    /// <summary>النص غير الموثق مميزًا في العرض والتصدير.</summary>
    public static string? UnverifiedLabel(string? text) =>
        string.IsNullOrWhiteSpace(text) ? null : $"{text.Trim()} (غير موثق)";

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
