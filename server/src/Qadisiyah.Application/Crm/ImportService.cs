using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Crm;

public static class ImportKinds
{
    public const string Parties = "parties";
    public const string Catalog = "catalog";
}

public static class ImportRowStatus
{
    public const string New = "new";
    public const string Existing = "existing";
    public const string Duplicate = "duplicate";
    public const string Invalid = "invalid";
    public const string Review = "review";
}

/// <param name="Values">قيم الحقول كما قُرئت (name/phone/grade/type أو material/manufacturer/grade/country).</param>
public sealed record ImportRowResult(int Row, string Status, IReadOnlyDictionary<string, string> Values,
    IReadOnlyList<string> Notes);

public sealed record ImportCounts(int New, int Existing, int Duplicate, int Invalid, int Review);

/// <param name="Mapping">الحقل ← رقم العمود (من صفر) كما استُخدم؛ يرسله التطبيق معدلًا للتعيين اليدوي.</param>
/// <param name="PreviousImportAt">نفس الملف استُورد من قبل بهذا التاريخ (تنبيه لا منع).</param>
public sealed record ImportResult(Guid? ImportId, bool Committed, string Kind, IReadOnlyList<string> Headers,
    IReadOnlyDictionary<string, int> Mapping, ImportCounts Counts, IReadOnlyList<ImportRowResult> Rows,
    DateTimeOffset? PreviousImportAt);

/// <summary>
/// الاستيراد السريع من Excel: معاينة أولًا (لا تكتب شيئًا) ثم تنفيذ الصفوف السليمة فقط.
/// <list type="bullet">
/// <item>العملاء والموردون: أي حقلين من (الاسم، الهاتف، Grade، النوع). بلا نوع ← «غير مصنف» دون تخمين،
/// الرقم غير الصحيح ← مراجعة، صفوف نفس الشركة ← بطاقة واحدة بكل الـ Grades، الموجود لا يتكرر،
/// والسجل غير الظاهر للمستخدم لا تُكشف بياناته.</item>
/// <item>الكتالوج: الخامة والشركة والـ Grade وبلد الصنع؛ يعيد استخدام الموجود، ونفس الكود لشركة أخرى مسموح،
/// والغامض يُعلَّم للمراجعة.</item>
/// </list>
/// معرف العملية ثابت من التطبيق: إعادة الإرسال تعيد النتيجة المحفوظة دون تكرار.
/// </summary>
public sealed class ImportService(
    IAppDbContext db,
    ICurrentUser user,
    PartyAccess access,
    ReferenceService reference,
    TimeProvider clock)
{
    public const long MaxFileBytes = 5 * 1024 * 1024;
    private const int MaxImportRows = 5000;

    public static readonly IReadOnlyDictionary<string, string[]> PartyColumns = new Dictionary<string, string[]>
    {
        ["name"] = ["الاسم", "اسم", "اسم الشركه", "الشركه", "اسم العميل", "اسم المورد", "العميل", "المورد", "name", "company", "company name"],
        ["phone"] = ["الهاتف", "هاتف", "رقم الهاتف", "التليفون", "تليفون", "الموبايل", "موبايل", "الرقم", "رقم", "جوال", "phone", "mobile", "tel", "telephone"],
        ["grade"] = ["grade", "الجريد", "جريد", "الدرجه", "كود الخامه", "الخامه", "grades"],
        ["type"] = ["النوع", "نوع", "التصنيف", "عميل او مورد", "عميل/مورد", "type", "role"],
    };

    public static readonly IReadOnlyDictionary<string, string[]> CatalogColumns = new Dictionary<string, string[]>
    {
        ["material"] = ["الخامه", "نوع الخامه", "خامه", "material", "material type", "type"],
        ["manufacturer"] = ["الشركه", "الشركه المصنعه", "المصنع", "الشركة المصنعة", "manufacturer", "maker", "producer", "company"],
        ["grade"] = ["grade", "الجريد", "جريد", "الدرجه", "الكود", "code"],
        ["country"] = ["البلد", "بلد الصنع", "بلد المنشا", "المنشا", "الدوله", "country", "origin", "country of origin"],
    };

    public bool CanImport => user.Has(Permissions.ImportRun);

    public bool CanExportCatalog => user.Has(Permissions.ReportsExport) || user.Has(Permissions.MasterDataManage);

    public Task<Result<ImportResult>> PreviewAsync(string kind, Stream file, IReadOnlyDictionary<string, int>? mapping,
        CancellationToken ct) => RunAsync(kind, null, file, mapping, ct);

    public Task<Result<ImportResult>> CommitAsync(string kind, Guid importId, Stream file,
        IReadOnlyDictionary<string, int>? mapping, CancellationToken ct) =>
        importId == Guid.Empty
            ? Task.FromResult<Result<ImportResult>>(AppError.Validation("معرف عملية الاستيراد مطلوب"))
            : RunAsync(kind, importId, file, mapping, ct);

    private async Task<Result<ImportResult>> RunAsync(string kind, Guid? importId, Stream file,
        IReadOnlyDictionary<string, int>? mapping, CancellationToken ct)
    {
        if (!CanImport)
            return AppError.Forbidden();
        if (kind is not (ImportKinds.Parties or ImportKinds.Catalog))
            return AppError.Validation("نوع استيراد غير معروف");

        if (importId is { } id && await db.ImportBatches.AsNoTracking().FirstOrDefaultAsync(b => b.Id == id, ct) is { } done)
        {
            if (done.CreatedBy != user.UserId || done.Kind != kind)
                return AppError.Conflict("import.id_taken", "معرف عملية الاستيراد مستخدم بالفعل");
            return JsonSerializer.Deserialize<ImportResult>(done.Summary, Json)!;
        }

        using var buffer = new MemoryStream();
        await file.CopyToAsync(buffer, ct);
        if (buffer.Length > MaxFileBytes)
            return AppError.Validation("حجم الملف أكبر من 5 ميجابايت");
        var sha = Convert.ToHexStringLower(SHA256.HashData(buffer.ToArray()));
        buffer.Position = 0;
        List<string[]> sheet;
        try
        {
            sheet = XlsxReader.Read(buffer);
        }
        catch (InvalidDataException e)
        {
            return AppError.Validation(e.Message, "import.invalid_file");
        }
        if (sheet.Count < 2)
            return AppError.Validation("الملف لا يحتوي على بيانات بعد صف العناوين", "import.empty");
        if (sheet.Count - 1 > MaxImportRows)
            return AppError.Validation($"الحد الأقصى {MaxImportRows} صف في الملف الواحد", "import.too_many_rows");

        var headers = sheet[0].Select(h => h.Trim()).ToList();
        var columns = kind == ImportKinds.Parties ? PartyColumns : CatalogColumns;
        var map = ResolveMapping(headers, columns, mapping);
        if (map.Count < 2)
            return AppError.Validation("تعذر التعرف على الأعمدة. حدد عمودين على الأقل يدويًا", "import.mapping");

        var rows = sheet.Skip(1).Select((cells, i) => (Row: i + 2, Values: columns.Keys.ToDictionary(k => k,
                k => map.TryGetValue(k, out var col) && col < cells.Length ? cells[col].Trim() : "")))
            .Where(r => r.Values.Values.Any(v => v.Length > 0))
            .ToList();

        var commit = importId is not null;
        var results = kind == ImportKinds.Parties
            ? await PartiesAsync(rows, commit, ct)
            : await CatalogAsync(rows, commit, ct);
        if (!results.IsSuccess)
            return results.Error!;

        var previous = await db.ImportBatches.AsNoTracking()
            .Where(b => b.FileSha256 == sha && b.Kind == kind)
            .OrderByDescending(b => b.CreatedAt).Select(b => (DateTimeOffset?)b.CreatedAt).FirstOrDefaultAsync(ct);
        var list = results.Value!;
        var counts = new ImportCounts(
            list.Count(r => r.Status == ImportRowStatus.New), list.Count(r => r.Status == ImportRowStatus.Existing),
            list.Count(r => r.Status == ImportRowStatus.Duplicate), list.Count(r => r.Status == ImportRowStatus.Invalid),
            list.Count(r => r.Status == ImportRowStatus.Review));
        var result = new ImportResult(importId, commit, kind, headers, map, counts, list, previous);
        if (!commit)
            return result;

        var now = clock.GetUtcNow();
        db.ImportBatches.Add(new ImportBatch
        {
            Id = importId!.Value,
            Kind = kind,
            FileSha256 = sha,
            CreatedBy = user.UserId,
            CreatedAt = now,
            Summary = JsonSerializer.Serialize(result, Json),
        });
        db.Audit(user, clock, $"import.{kind}", "import", importId.Value, new { counts, sha });
        await db.SaveChangesAsync(ct);
        return result;
    }

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>التعيين اليدوي أولًا، ثم مطابقة أسماء الأعمدة المعروفة؛ لا يُستخدم عمود لحقلين.</summary>
    private static Dictionary<string, int> ResolveMapping(List<string> headers,
        IReadOnlyDictionary<string, string[]> columns, IReadOnlyDictionary<string, int>? manual)
    {
        var map = new Dictionary<string, int>();
        foreach (var (field, col) in manual ?? new Dictionary<string, int>())
            if (columns.ContainsKey(field) && col >= 0 && col < headers.Count && !map.ContainsValue(col))
                map[field] = col;
        var normalized = headers.Select(TextNormalizer.Normalize).ToList();
        foreach (var (field, names) in columns)
        {
            if (map.ContainsKey(field) || (manual?.ContainsKey(field) ?? false))
                continue;
            var keys = names.Select(TextNormalizer.Normalize).ToHashSet();
            var col = normalized.FindIndex(h => keys.Contains(h) && !map.ContainsValue(normalized.IndexOf(h)));
            if (col < 0)
                col = Enumerable.Range(0, normalized.Count)
                    .FirstOrDefault(i => !map.ContainsValue(i) && keys.Any(k => k.Length >= 3 && normalized[i].Contains(k)), -1);
            if (col >= 0 && !map.ContainsValue(col))
                map[field] = col;
        }
        return map;
    }

    // ---------------- العملاء والموردون ----------------

    private sealed class PartyGroup
    {
        public required int FirstRow;
        public string? Name;
        public List<string> Phones { get; } = [];
        public List<string> Grades { get; } = [];
        public bool? Customer;
        public bool? Supplier;
        public List<int> Rows { get; } = [];
    }

    private async Task<Result<List<ImportRowResult>>> PartiesAsync(
        List<(int Row, Dictionary<string, string> Values)> rows, bool commit, CancellationToken ct)
    {
        var output = new Dictionary<int, (string Status, List<string> Notes)>();
        var groups = new List<PartyGroup>();
        var byKey = new Dictionary<string, PartyGroup>();

        foreach (var (row, v) in rows)
        {
            var notes = new List<string>();
            var filled = v.Count(x => x.Value.Length > 0);
            if (filled < 2)
            {
                output[row] = (ImportRowStatus.Invalid, ["يلزم حقلان على الأقل من: الاسم، الهاتف، Grade، النوع"]);
                continue;
            }
            var name = v["name"];
            if (name.Length is 1 or > 200)
            {
                output[row] = (ImportRowStatus.Review, ["الاسم قصير جدًا أو طويل جدًا"]);
                continue;
            }
            string? phone = null;
            if (v["phone"].Length > 0)
            {
                phone = PhoneNumber.Normalize(v["phone"]);
                if (phone is null)
                {
                    output[row] = (ImportRowStatus.Review, [$"رقم الهاتف غير صحيح: {v["phone"]}"]);
                    continue;
                }
            }
            if (name.Length == 0 && phone is null)
            {
                output[row] = (ImportRowStatus.Invalid, ["يلزم الاسم أو رقم الهاتف لتعريف الشركة"]);
                continue;
            }
            var type = ParseType(v["type"]);
            if (type is null)
            {
                output[row] = (ImportRowStatus.Review, [$"النوع غير مفهوم: «{v["type"]}». اكتب عميل أو مورد أو اتركه فارغًا"]);
                continue;
            }

            var nameKey = name.Length > 0 ? "n:" + TextNormalizer.Normalize(name) : null;
            var phoneKey = phone is null ? null : "p:" + phone;
            var group = (nameKey is not null ? byKey.GetValueOrDefault(nameKey) : null)
                ?? (phoneKey is not null ? byKey.GetValueOrDefault(phoneKey) : null);
            if (group is null)
            {
                group = new PartyGroup { FirstRow = row };
                groups.Add(group);
            }
            else
            {
                if (type.Value.Customer || type.Value.Supplier)
                {
                    if (group.Customer is not null
                        && (group.Customer != type.Value.Customer || group.Supplier != type.Value.Supplier)
                        && !(group.Customer == false && group.Supplier == false))
                    {
                        output[row] = (ImportRowStatus.Review, [$"النوع يختلف عن الصف {group.FirstRow} لنفس الشركة"]);
                        continue;
                    }
                }
                notes.Add($"دُمج مع الصف {group.FirstRow} في بطاقة واحدة");
            }
            group.Name ??= name.Length > 0 ? name : null;
            if (phone is not null && !group.Phones.Contains(phone) && group.Phones.Count < 5)
                group.Phones.Add(phone);
            foreach (var g in v["grade"].Split([',', '،', ';', '/', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                if (!group.Grades.Contains(g, StringComparer.OrdinalIgnoreCase))
                    group.Grades.Add(g);
            if (type.Value.Customer || type.Value.Supplier || group.Customer is null)
            {
                group.Customer = type.Value.Customer;
                group.Supplier = type.Value.Supplier;
            }
            group.Rows.Add(row);
            if (nameKey is not null)
                byKey.TryAdd(nameKey, group);
            if (phoneKey is not null)
                byKey.TryAdd(phoneKey, group);
            output[row] = (group.FirstRow == row ? ImportRowStatus.New : ImportRowStatus.Duplicate, notes);
        }

        // كتالوج الـ Grades للربط: كود واحد لشركة واحدة فقط، وإلا يُترك للاستكمال.
        var codes = groups.SelectMany(g => g.Grades).Select(TextNormalizer.NormalizeCode).Where(c => c.Length > 0)
            .Distinct().ToList();
        var gradeRows = await db.Grades.AsNoTracking().Where(g => g.IsActive && codes.Contains(g.NormalizedCode))
            .Select(g => new { g.Id, g.MaterialId, g.NormalizedCode }).ToListAsync(ct);
        var gradesByCode = gradeRows.GroupBy(g => g.NormalizedCode).ToDictionary(g => g.Key, g => g.ToList());

        var myRep = commit ? await reference.EnsureMyRepresentativeAsync(ct) : null;
        var now = clock.GetUtcNow();
        var today = BusinessClock.Today(clock);

        foreach (var group in groups)
        {
            var notes = output[group.FirstRow].Notes;
            void Mark(string status, string note)
            {
                output[group.FirstRow] = (status, [.. notes, note]);
                foreach (var r in group.Rows.Where(r => r != group.FirstRow))
                    output[r] = (status == ImportRowStatus.Review ? ImportRowStatus.Review : output[r].Status, output[r].Notes);
            }

            var linked = new List<(Guid Grade, Guid Material, string Code)>();
            foreach (var code in group.Grades)
            {
                var found = gradesByCode.GetValueOrDefault(TextNormalizer.NormalizeCode(code)) ?? [];
                if (found.Count == 1)
                    linked.Add((found[0].Id, found[0].MaterialId, code));
                else
                    notes.Add(found.Count == 0
                        ? $"Grade «{code}» غير موجود في الكتالوج — يحتاج استكمال"
                        : $"Grade «{code}» مسجل لأكثر من شركة — حدده من ملف السجل");
            }

            // مطابقة الموجود بالرقم ثم بالاسم المطابق تمامًا.
            var normalizedName = group.Name is null ? null : TextNormalizer.Normalize(group.Name);
            var existing = await db.Parties
                .Include(p => p.Interests).Include(p => p.Products)
                .Where(p => p.DeletedAt == null
                    && (db.PartyPhones.Any(ph => ph.PartyId == p.Id && group.Phones.Contains(ph.E164))
                        || (normalizedName != null && p.NormalizedName == normalizedName)))
                .FirstOrDefaultAsync(ct);

            if (existing is not null)
            {
                if (!await access.CanViewAsync(existing, ct))
                {
                    Mark(ImportRowStatus.Review, "هذه الشركة أو الرقم مسجل بالفعل في النظام. إذا كانت تابعة لك تواصل مع الإدارة.");
                    continue;
                }
                var added = commit ? AddGradesToExisting(existing, linked, notes) : PlanAddToExisting(existing, linked);
                if (commit && added > 0)
                {
                    existing.Touch(user.UserId, now);
                    db.Audit(user, clock, "party.import_merged", "party", existing.Id, new { grades = added });
                }
                Mark(ImportRowStatus.Existing, added > 0
                    ? $"موجود مسبقًا باسم «{existing.Name}» — أُضيف {added} Grade"
                    : $"موجود مسبقًا باسم «{existing.Name}» — لا جديد");
                continue;
            }

            var customer = group.Customer ?? false;
            var supplier = group.Supplier ?? false;
            var unclassified = !customer && !supplier;
            if (unclassified
                ? !(user.Has(Permissions.CustomersCreate) || user.Has(Permissions.SuppliersCreate))
                : !access.CanCreate(customer, supplier))
            {
                Mark(ImportRowStatus.Review, supplier ? "لا تملك صلاحية إضافة موردين" : "لا تملك صلاحية إضافة عملاء");
                continue;
            }
            if (unclassified)
                notes.Add("غير مصنف — يحتاج تحديد النوع");
            if (group.Name is null)
                notes.Add("بدون اسم — يحتاج استكمال");
            if (group.Phones.Count == 0)
                notes.Add("بدون رقم هاتف — يحتاج استكمال");
            output[group.FirstRow] = (ImportRowStatus.New, notes);
            if (!commit)
                continue;

            var name = group.Name?.Trim() ?? $"بدون اسم ({group.Phones[0]})";
            var party = new Party
            {
                Id = Guid.CreateVersion7(),
                Name = name,
                NormalizedName = TextNormalizer.Normalize(name),
                NameMissing = group.Name is null,
                IsCustomer = customer,
                IsSupplier = supplier,
                RepresentativeId = myRep,
                RecordDate = today,
            };
            party.Stamp(user.UserId, now);
            party.Phones.AddRange(group.Phones.Select((p, i) => new PartyPhone { PartyId = party.Id, E164 = p, IsPrimary = i == 0 }));
            AddGrades(party, linked, notes);
            db.Parties.Add(party);
            db.Audit(user, clock, "party.created", "party", party.Id,
                new { party.IsCustomer, party.IsSupplier, source = "import" });
        }

        return rows.Select(r => new ImportRowResult(r.Row, output[r.Row].Status, r.Values, output[r.Row].Notes)).ToList();
    }

    private static (bool Customer, bool Supplier)? ParseType(string value)
    {
        var t = TextNormalizer.Normalize(value);
        if (t.Length == 0 || t is "غير مصنف" or "غير محدد")
            return (false, false);
        var customer = t.Contains("عميل") || t.Contains("customer") || t.Contains("client") || t is "ع";
        var supplier = t.Contains("مورد") || t.Contains("supplier") || t.Contains("vendor") || t is "م";
        if (t.Contains("كلاهما") || t.Contains("both"))
            customer = supplier = true;
        return customer || supplier ? (customer, supplier) : null;
    }

    private static int PlanAddToExisting(Party party, List<(Guid Grade, Guid Material, string Code)> linked) =>
        linked.Count(l => (party.IsCustomer && party.Interests.All(i => i.GradeId != l.Grade))
            || (party.IsSupplier && party.Products.All(p => p.GradeId != l.Grade))
            || (!party.IsCustomer && !party.IsSupplier && party.PendingGradeId is null));

    private int AddGradesToExisting(Party party, List<(Guid Grade, Guid Material, string Code)> linked, List<string> notes)
    {
        var before = party.Interests.Count + party.Products.Count + (party.PendingGradeId is null ? 0 : 1);
        AddGrades(party, linked, notes);
        return party.Interests.Count + party.Products.Count + (party.PendingGradeId is null ? 0 : 1) - before;
    }

    private void AddGrades(Party party, List<(Guid Grade, Guid Material, string Code)> linked, List<string> notes)
    {
        var customerSide = party.IsCustomer && user.Has(Permissions.CustomersCreate);
        var supplierSide = party.IsSupplier && access.CanSeeSuppliers && user.Has(Permissions.SuppliersCreate);
        var extra = new List<string>();
        foreach (var (gradeId, materialId, code) in linked)
        {
            if (customerSide && party.Interests.All(i => i.GradeId != gradeId))
            {
                var interest = new CustomerInterest { PartyId = party.Id, MaterialId = materialId, GradeId = gradeId };
                party.Interests.Add(interest);
                db.CustomerInterests.Add(interest);
            }
            if (supplierSide && party.Products.All(p => p.GradeId != gradeId))
            {
                var product = new SupplierProduct { PartyId = party.Id, MaterialId = materialId, GradeId = gradeId };
                party.Products.Add(product);
                db.SupplierProducts.Add(product);
            }
            if (!party.IsCustomer && !party.IsSupplier)
            {
                if (party.PendingGradeId is null)
                    party.PendingGradeId = gradeId;
                else if (party.PendingGradeId != gradeId)
                    extra.Add(code);
            }
        }
        if (extra.Count > 0)
        {
            // سجل غير مصنف يحمل Grade واحدًا معلقًا؛ الباقي يُحفظ في الملاحظات حتى لا يضيع.
            var line = "Grades من الاستيراد: " + string.Join("، ", extra);
            party.Notes = string.IsNullOrEmpty(party.Notes) ? line : $"{party.Notes}\n{line}";
            notes.Add("Grades إضافية حُفظت في الملاحظات حتى يُحدد النوع");
        }
    }

    // ---------------- الكتالوج ----------------

    private async Task<Result<List<ImportRowResult>>> CatalogAsync(
        List<(int Row, Dictionary<string, string> Values)> rows, bool commit, CancellationToken ct)
    {
        var canRegister = user.Has(Permissions.MasterDataManage) || user.Has(Permissions.CustomersCreate)
            || user.Has(Permissions.SuppliersCreate);
        if (!canRegister)
            return AppError.Forbidden();

        var materials = await db.Materials.Include(m => m.Aliases).ToListAsync(ct);
        var makers = await db.Manufacturers.ToListAsync(ct);
        var grades = await db.Grades.Include(g => g.Origins).ToListAsync(ct);
        var countries = await db.LookupItems.AsNoTracking().Where(l => l.Category == LookupCategories.Country)
            .ToListAsync(ct);
        var now = clock.GetUtcNow();
        var output = new List<ImportRowResult>();
        var addedGrades = new HashSet<Guid>();

        Material? FindMaterial(string value)
        {
            var key = TextNormalizer.NormalizeCode(Synonyms.MaterialCode(TextNormalizer.Normalize(value)) ?? value);
            return materials.FirstOrDefault(m => TextNormalizer.NormalizeCode(m.Code) == key
                || m.Aliases.Any(a => a.Normalized == key));
        }

        Manufacturer? FindMaker(string value)
        {
            var variants = Synonyms.MakerVariants(TextNormalizer.Normalize(value));
            return makers.FirstOrDefault(m => variants.Contains(m.NormalizedName));
        }

        LookupItem? FindCountry(string value)
        {
            var key = TextNormalizer.Normalize(value);
            return countries.FirstOrDefault(c => TextNormalizer.Normalize(c.NameAr) == key
                || string.Equals(c.Code, value.Trim(), StringComparison.OrdinalIgnoreCase)
                || (c.NameEn is not null && TextNormalizer.Normalize(c.NameEn) == key));
        }

        foreach (var (row, v) in rows)
        {
            var notes = new List<string>();
            ImportRowResult Done(string status) => new(row, status, v, notes);
            var (materialText, makerText, codeText, countryText) = (v["material"], v["manufacturer"], v["grade"], v["country"]);
            if (v.Count(x => x.Value.Length > 0) < 2 && !(materialText.Length > 0 && v.Count(x => x.Value.Length > 0) == 1))
            {
                notes.Add("الصف لا يحتوي على بيانات كافية");
                output.Add(Done(ImportRowStatus.Invalid));
                continue;
            }
            if (materialText.Length == 0)
            {
                notes.Add("الخامة مطلوبة لكل صف");
                output.Add(Done(ImportRowStatus.Review));
                continue;
            }
            if (codeText.Length > 0 && makerText.Length == 0)
            {
                notes.Add("الشركة المصنّعة مطلوبة مع الـ Grade — لا يتم تخمينها");
                output.Add(Done(ImportRowStatus.Review));
                continue;
            }
            if (codeText.Length > 64 || TextNormalizer.NormalizeCode(codeText).Length == 0 && codeText.Length > 0)
            {
                notes.Add("كود الـ Grade غير صالح");
                output.Add(Done(ImportRowStatus.Review));
                continue;
            }

            var created = false;
            var material = FindMaterial(materialText);
            if (material is null)
            {
                var code = materialText.Trim().ToUpperInvariant();
                if (code.Length > 12 || !code.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or ' '))
                {
                    notes.Add($"الخامة «{materialText}» غير معروفة — أضفها من «إضافة نوع خامة» باختصارها (مثل PP)");
                    output.Add(Done(ImportRowStatus.Review));
                    continue;
                }
                material = new Material { Code = code, NameAr = code, SortOrder = 1000 };
                material.Aliases.Add(new MaterialAlias { Alias = code, Normalized = TextNormalizer.NormalizeCode(code) });
                materials.Add(material);
                notes.Add($"خامة جديدة: {code}");
                created = true;
                if (commit)
                {
                    db.Materials.Add(material);
                    db.Audit(user, clock, "masterdata.material_created", "material", material.Id, new { code, source = "import" });
                }
            }

            Manufacturer? maker = null;
            if (makerText.Length > 0)
            {
                maker = FindMaker(makerText);
                if (maker is null)
                {
                    if (makerText.Trim().Length > 120)
                    {
                        notes.Add("اسم الشركة طويل جدًا");
                        output.Add(Done(ImportRowStatus.Review));
                        continue;
                    }
                    maker = new Manufacturer { Name = makerText.Trim(), NormalizedName = TextNormalizer.Normalize(makerText) };
                    makers.Add(maker);
                    notes.Add($"شركة جديدة: {maker.Name}");
                    created = true;
                    if (commit)
                    {
                        db.Manufacturers.Add(maker);
                        db.Audit(user, clock, "masterdata.manufacturer_created", "manufacturer", maker.Id,
                            new { name = maker.Name, source = "import" });
                    }
                }
            }

            LookupItem? country = null;
            if (countryText.Length > 0)
            {
                country = FindCountry(countryText);
                if (country is null)
                    notes.Add($"بلد الصنع «{countryText}» غير معروف — لم يُربط (يضيفه المدير من الكتالوج)");
            }

            if (codeText.Length == 0)
            {
                output.Add(Done(created ? ImportRowStatus.New : ImportRowStatus.Existing));
                continue;
            }

            var normalizedCode = TextNormalizer.NormalizeCode(codeText);
            var grade = grades.FirstOrDefault(g => g.MaterialId == material.Id && g.ManufacturerId == maker!.Id
                && g.NormalizedCode == normalizedCode);
            if (grade is not null)
            {
                if (country is not null && grade.Origins.All(o => o.CountryId != country.Id))
                {
                    var origin = new GradeOrigin { GradeId = grade.Id, CountryId = country.Id };
                    grade.Origins.Add(origin);
                    notes.Add($"أُضيف بلد الصنع {country.NameAr}");
                    if (commit)
                    {
                        db.GradeOrigins.Add(origin);
                        db.Audit(user, clock, "masterdata.grade_origin_added", "grade", grade.Id, new { country = country.Code });
                    }
                    output.Add(Done(ImportRowStatus.Existing));
                }
                else
                {
                    var inFile = addedGrades.Contains(grade.Id);
                    notes.Add(inFile ? "مكرر داخل الملف" : "موجود مسبقًا");
                    output.Add(Done(inFile ? ImportRowStatus.Duplicate : ImportRowStatus.Existing));
                }
                continue;
            }

            if (grades.Any(g => g.MaterialId == material.Id && g.NormalizedCode == normalizedCode))
                notes.Add("نفس الكود مسجل لشركة أخرى — أُضيف كـ Grade مستقل لهذه الشركة");
            grade = new Grade
            {
                MaterialId = material.Id,
                ManufacturerId = maker!.Id,
                Code = codeText.Trim(),
                NormalizedCode = normalizedCode,
                IsVerified = true,
                CreatedBy = user.UserId,
                CreatedAt = now,
            };
            if (country is not null)
                grade.Origins.Add(new GradeOrigin { GradeId = grade.Id, CountryId = country.Id });
            grades.Add(grade);
            addedGrades.Add(grade.Id);
            if (commit)
            {
                db.Grades.Add(grade);
                db.Audit(user, clock, "masterdata.grade_created", "grade", grade.Id,
                    new { grade.MaterialId, grade.ManufacturerId, code = grade.Code, source = "import" });
            }
            output.Add(Done(ImportRowStatus.New));
        }
        return output;
    }

    // ---------------- القوالب والتصدير ----------------

    public static (byte[] Content, string FileName)? Template(string kind) => kind switch
    {
        ImportKinds.Parties => (XlsxWriter.Write("العملاء والموردون", ["الاسم", "الهاتف", "Grade", "النوع"],
        [
            ["شركة النور للبلاستيك", "01001234567", "HP500N", "عميل"],
            ["مؤسسة الأمل", "01112345678", "", "مورد"],
            ["", "01223456789", "M80T", ""],
        ]), "قالب-العملاء-والموردين.xlsx"),
        ImportKinds.Catalog => (XlsxWriter.Write("الكتالوج", ["الخامة", "الشركة المصنعة", "Grade", "بلد الصنع"],
        [
            ["PP", "SABIC", "500P", "السعودية"],
            ["HDPE", "Borouge", "FB5600", "الإمارات"],
        ]), "قالب-الكتالوج.xlsx"),
        _ => null,
    };

    public async Task<Result<(byte[] Content, string FileName)>> ExportCatalogAsync(CancellationToken ct)
    {
        if (!CanExportCatalog)
            return AppError.Forbidden();
        var rows = await (
            from g in db.Grades.AsNoTracking()
            join m in db.Materials.AsNoTracking() on g.MaterialId equals m.Id
            join f in db.Manufacturers.AsNoTracking() on g.ManufacturerId equals f.Id into fj
            from f in fj.DefaultIfEmpty()
            orderby m.Code, g.Code
            select new { m.Code, Maker = f == null ? "" : f.Name, Grade = g.Code, g.IsActive, g.Id })
            .ToListAsync(ct);
        var origins = await (
            from o in db.GradeOrigins.AsNoTracking()
            join c in db.LookupItems.AsNoTracking() on o.CountryId equals c.Id
            select new { o.GradeId, c.NameAr }).ToListAsync(ct);
        var byGrade = origins.GroupBy(o => o.GradeId).ToDictionary(g => g.Key, g => string.Join("، ", g.Select(x => x.NameAr)));
        var content = XlsxWriter.Write("الكتالوج", ["الخامة", "الشركة المصنعة", "Grade", "بلد الصنع", "الحالة"],
            rows.Select(r => (IReadOnlyList<object?>)[r.Code, r.Maker, r.Grade, byGrade.GetValueOrDefault(r.Id, ""),
                r.IsActive ? "نشط" : "موقوف"]));
        db.Audit(user, clock, "export.catalog", "catalog", Guid.Empty, new { rows = rows.Count });
        await db.SaveChangesAsync(ct);
        return (content, $"الكتالوج-{BusinessClock.Today(clock):yyyy-MM-dd}.xlsx");
    }
}
