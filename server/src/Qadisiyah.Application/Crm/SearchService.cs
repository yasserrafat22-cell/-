using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

public sealed record SearchCard(
    Guid PartyId,
    string Name,
    bool IsCustomer,
    bool IsSupplier,
    string? Phone,
    string? ContactName,
    string? Email,
    IReadOnlyList<SpecInfo> Specs,
    IReadOnlyList<string> Reasons,
    bool Exact,
    int Score);

public sealed record SearchSuggestion(string Kind, Guid Id, string Label, Guid? MaterialId, Guid? ManufacturerId);

public sealed record SearchResult(
    IReadOnlyList<SearchSuggestion> Suggestions,
    IReadOnlyList<SearchCard> Suppliers,
    IReadOnlyList<SearchCard> Customers);

/// <summary>
/// البحث الذكي اللحظي: بالاسم أو جزء منه، أو اسم موظف، أو جزء من الهاتف، أو الخامة/الشركة/
/// الـ Grade/بلد الصنع. النتائج قسمان: الموردون أولًا (لمن يطّلع عليهم فقط) ثم العملاء المناسبون،
/// ولكل بطاقة سبب المطابقة. البحث باسم مورد يعرض العملاء الذين يحتاجون خاماته، والبحث باسم
/// عميل يعرض الموردين المناسبين لاحتياجاته. لا سعر ولا توافر مُخترع.
/// </summary>
public sealed class SearchService(IAppDbContext db, PartyAccess access, MaterialSpecs specs)
{
    private const int MaxCards = 50;

    private sealed record Row(Guid PartyId, Guid MaterialId, Guid? GradeId, Guid? MakerId, Guid? OriginId, bool Open);

    private sealed class Acc
    {
        public HashSet<string> Reasons { get; } = [];
        public HashSet<ResolvedSpec> Specs { get; } = [];
        public bool Exact { get; set; }
        public int Score { get; set; }

        public void Add(string reason, ResolvedSpec? spec, int score, bool exact)
        {
            Reasons.Add(reason);
            if (spec is not null)
                Specs.Add(spec);
            Score = Math.Max(Score, score);
            Exact |= exact;
        }
    }

    public async Task<SearchResult> SearchAsync(string? q, Guid? materialId, Guid? manufacturerId, Guid? gradeId,
        CancellationToken ct)
    {
        var text = q?.Trim() ?? "";
        var normalized = TextNormalizer.Normalize(text);
        var code = TextNormalizer.NormalizeCode(text);
        if (normalized.Length < 2 && materialId is null && manufacturerId is null && gradeId is null)
            return new SearchResult([], [], []);

        // 1) المواصفات المقصودة من الكتالوج الموحد.
        var materialIds = new HashSet<Guid>();
        var makerIds = new HashSet<Guid>();
        var gradeIds = new HashSet<Guid>();
        var suggestions = new List<SearchSuggestion>();
        if (materialId is { } m) materialIds.Add(m);
        if (manufacturerId is { } mf) makerIds.Add(mf);
        if (gradeId is { } g) gradeIds.Add(g);
        var explicitSpec = materialIds.Count + makerIds.Count + gradeIds.Count > 0;
        if (normalized.Length >= 2)
        {
            var upper = Synonyms.MaterialCode(normalized) ?? text.ToUpperInvariant();
            var mats = await db.Materials.AsNoTracking()
                .Where(x => x.Code == upper || x.Aliases.Any(a => a.Normalized == code))
                .Select(x => new { x.Id, x.Code }).ToListAsync(ct);
            var variants = Synonyms.MakerVariants(normalized);
            var makers = (await db.Manufacturers.AsNoTracking().Where(x => x.IsActive)
                    .Select(x => new { x.Id, x.Name, x.NormalizedName }).ToListAsync(ct))
                .Where(x => variants.Any(v => x.NormalizedName.Contains(v, StringComparison.Ordinal)))
                .ToList();
            var grades = code.Length >= 2
                ? await db.Grades.AsNoTracking().Where(x => x.IsActive && x.NormalizedCode.Contains(code))
                    .Select(x => new { x.Id, x.Code, x.MaterialId, x.ManufacturerId }).Take(60).ToListAsync(ct)
                : [];
            // شركة مصنّعة: كل جريداتها اقتراحات يختار منها المستخدم الخامة أو الـ Grade.
            var makerSet = makers.Select(x => x.Id).ToList();
            var makerGrades = makerSet.Count > 0
                ? await db.Grades.AsNoTracking().Where(x => x.IsActive && x.ManufacturerId != null
                        && makerSet.Contains(x.ManufacturerId.Value))
                    .Select(x => new { x.Id, x.Code, x.MaterialId, x.ManufacturerId }).Take(60).ToListAsync(ct)
                : [];
            var materialCodes = await db.Materials.AsNoTracking().ToDictionaryAsync(x => x.Id, x => x.Code, ct);
            suggestions.AddRange(mats.Select(x => new SearchSuggestion("material", x.Id, x.Code, x.Id, null)));
            suggestions.AddRange(makers.Select(x => new SearchSuggestion("manufacturer", x.Id, x.Name, null, x.Id)));
            foreach (var mm in makerGrades.Select(x => x.MaterialId).Distinct())
                suggestions.Add(new SearchSuggestion("material", mm, materialCodes.GetValueOrDefault(mm, ""), mm,
                    makers.Count == 1 ? makers[0].Id : null));
            suggestions.AddRange(grades.Concat(makerGrades).DistinctBy(x => x.Id).Select(x => new SearchSuggestion("grade",
                x.Id, $"{materialCodes.GetValueOrDefault(x.MaterialId, "")} · {x.Code}", x.MaterialId, x.ManufacturerId)));
            if (!explicitSpec)
            {
                materialIds.UnionWith(mats.Select(x => x.Id));
                makerIds.UnionWith(makerSet);
                gradeIds.UnionWith(grades.Select(x => x.Id));
            }
        }

        // 2) الأطراف المطابقة مباشرة (اسم، جزء من الهاتف، اسم موظف) ضمن الصلاحيات.
        var customersQ = access.VisibleAs(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null), true, false);
        var suppliersQ = access.CanSeeSuppliers
            ? access.VisibleAs(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null), false, true)
            : db.Parties.Where(_ => false);
        // جزء من الهاتف: أرقام فقط (5 على الأقل)؛ الصفر في البداية يُحذف لأن الأرقام بالصيغة الدولية.
        var allDigits = new string(text.Where(char.IsAsciiDigit).ToArray());
        var byPhone = allDigits.Length >= 5 && allDigits.Length == text.Count(c => !char.IsWhiteSpace(c) && c != '+');
        var digits = allDigits.TrimStart('0');
        byPhone &= digits.Length > 0;
        var directIds = normalized.Length >= 2 && !explicitSpec
            ? await db.Parties.AsNoTracking().Where(p => p.DeletedAt == null && (p.NormalizedName.Contains(normalized)
                    || (byPhone && p.Phones.Any(ph => ph.E164.Contains(digits)))
                    || db.PartyContacts.Any(c => c.PartyId == p.Id && c.DeletedAt == null
                        && (c.Name.Contains(text) || (byPhone && c.Mobile != null && c.Mobile.Contains(digits))))))
                .Select(p => p.Id).Take(200).ToListAsync(ct)
            : [];
        var directCustomers = await customersQ.Where(p => directIds.Contains(p.Id)).Select(p => p.Id).ToListAsync(ct);
        var directSuppliers = await suppliersQ.Where(p => directIds.Contains(p.Id)).Select(p => p.Id).ToListAsync(ct);

        // 3) صفوف المواصفات (منتجات الموردين واحتياجات العملاء) المرتبطة بالبحث.
        var makerOf = await db.Grades.AsNoTracking().ToDictionaryAsync(x => x.Id, x => x.ManufacturerId, ct);
        var products = await (from sp in db.SupplierProducts.AsNoTracking()
                              join p in suppliersQ on sp.PartyId equals p.Id
                              where sp.IsActive
                              select new { sp.PartyId, sp.MaterialId, sp.GradeId, sp.OriginCountryId })
            .ToListAsync(ct);
        var interests = await (from i in db.CustomerInterests.AsNoTracking()
                               join p in customersQ on i.PartyId equals p.Id
                               select new { i.PartyId, i.MaterialId, i.GradeId, i.OriginCountryId, i.OpenSpec })
            .ToListAsync(ct);
        var productRows = products.Select(x => new Row(x.PartyId, x.MaterialId, x.GradeId,
            x.GradeId is { } gg ? makerOf.GetValueOrDefault(gg) : null, x.OriginCountryId, false)).ToList();
        var interestRows = interests.Select(x => new Row(x.PartyId, x.MaterialId, x.GradeId,
            x.GradeId is { } gg ? makerOf.GetValueOrDefault(gg) : null, x.OriginCountryId, x.OpenSpec)).ToList();

        var suppliers = new Dictionary<Guid, Acc>();
        var customers = new Dictionary<Guid, Acc>();
        Acc For(Dictionary<Guid, Acc> d, Guid id) => d.TryGetValue(id, out var a) ? a : d[id] = new Acc();
        static ResolvedSpec Spec(Row r) => new(r.MaterialId, r.GradeId, r.OriginId, r.Open);

        var describe = await specs.DescribeAsync(productRows.Select(Spec).Concat(interestRows.Select(Spec)), ct);
        string Label(Row r) => PartyService.SpecLabel(describe(Spec(r)));

        // بحث بالمواصفات.
        if (materialIds.Count + makerIds.Count + gradeIds.Count > 0)
        {
            foreach (var r in productRows)
            {
                if (r.GradeId is { } pg && gradeIds.Contains(pg))
                    For(suppliers, r.PartyId).Add($"يوفّر {Label(r)}", Spec(r), 100, true);
                else if (r.MakerId is { } mk && makerIds.Contains(mk) && (materialIds.Count == 0 || materialIds.Contains(r.MaterialId)))
                    For(suppliers, r.PartyId).Add($"يوفّر {Label(r)}", Spec(r), 80, gradeIds.Count == 0);
                else if (materialIds.Contains(r.MaterialId) && makerIds.Count == 0 && gradeIds.Count == 0)
                    For(suppliers, r.PartyId).Add($"يوفّر {Label(r)}", Spec(r), 60, true);
            }
            var searchedMaterials = materialIds.ToHashSet();
            var gradeMaterials = await db.Grades.AsNoTracking().Where(x => gradeIds.Contains(x.Id))
                .Select(x => x.MaterialId).ToListAsync(ct);
            searchedMaterials.UnionWith(gradeMaterials);
            foreach (var r in interestRows)
            {
                if (r.GradeId is { } ig && gradeIds.Contains(ig))
                    For(customers, r.PartyId).Add($"يحتاج {Label(r)}", Spec(r), 100, true);
                else if (r.Open && searchedMaterials.Contains(r.MaterialId))
                    For(customers, r.PartyId).Add($"يحتاج {Label(r)} (يقبل أي شركة)", Spec(r), 70, false);
                else if (r.MakerId is { } mk && makerIds.Contains(mk))
                    For(customers, r.PartyId).Add($"يحتاج {Label(r)}", Spec(r), 80, gradeIds.Count == 0);
                else if (r.GradeId is null && !r.Open && searchedMaterials.Contains(r.MaterialId))
                    For(customers, r.PartyId).Add($"يحتاج خامة {Label(r)} دون تحديد Grade", Spec(r), 40, false);
            }
        }

        // بحث باسم مورد: العملاء الذين يحتاجون خاماته.
        foreach (var supplierId in directSuppliers)
        {
            For(suppliers, supplierId).Add("مطابقة بالاسم أو الهاتف أو جهة الاتصال", null, 90, true);
            foreach (var p in productRows.Where(x => x.PartyId == supplierId))
            foreach (var need in interestRows.Where(x => x.MaterialId == p.MaterialId))
            {
                if (need.GradeId is { } ng && ng == p.GradeId)
                    For(customers, need.PartyId).Add($"يحتاج {Label(need)} الذي يوفره المورد", Spec(need), 95, true);
                else if (need.Open)
                    For(customers, need.PartyId).Add($"يقبل أي شركة لخامة {Label(need)}", Spec(need), 65, false);
                else if (need.MakerId is { } nm && nm == p.MakerId)
                    For(customers, need.PartyId).Add($"يحتاج {Label(need)} من نفس الشركة المصنّعة", Spec(need), 55, false);
            }
        }

        // بحث باسم عميل: الموردون المناسبون لاحتياجاته (لمن يطّلع على الموردين فقط).
        foreach (var customerId in directCustomers)
        {
            For(customers, customerId).Add("مطابقة بالاسم أو الهاتف أو جهة الاتصال", null, 90, true);
            foreach (var need in interestRows.Where(x => x.PartyId == customerId))
            foreach (var p in productRows.Where(x => x.MaterialId == need.MaterialId))
            {
                if (need.GradeId is { } ng && ng == p.GradeId
                    && (need.OriginId is null || p.OriginId is null || need.OriginId == p.OriginId))
                    For(suppliers, p.PartyId).Add($"يوفّر {Label(p)} الذي يحتاجه العميل", Spec(p), 95, true);
                else if (need.Open)
                    For(suppliers, p.PartyId).Add($"يوفّر {Label(p)} والعميل يقبل أي شركة", Spec(p), 70, true);
                else if (need.MakerId is { } nm && nm == p.MakerId)
                    For(suppliers, p.PartyId).Add($"بديل محتمل: {Label(p)} من نفس الشركة", Spec(p), 50, false);
            }
        }

        return new SearchResult(suggestions.DistinctBy(s => (s.Kind, s.Id, s.ManufacturerId)).Take(40).ToList(),
            await CardsAsync(suppliers, describe, ct), await CardsAsync(customers, describe, ct));
    }

    private async Task<List<SearchCard>> CardsAsync(Dictionary<Guid, Acc> found, Func<ResolvedSpec, SpecInfo> describe,
        CancellationToken ct)
    {
        var ranked = found.OrderByDescending(x => x.Value.Exact).ThenByDescending(x => x.Value.Score)
            .Take(MaxCards).ToList();
        var ids = ranked.Select(x => x.Key).ToList();
        var info = await db.Parties.AsNoTracking().Where(p => ids.Contains(p.Id))
            .Select(p => new
            {
                p.Id, p.Name, p.IsCustomer, p.IsSupplier, p.Email,
                Phone = p.Phones.OrderByDescending(ph => ph.IsPrimary).Select(ph => ph.E164).FirstOrDefault(),
                Contact = db.PartyContacts.Where(c => c.PartyId == p.Id && c.DeletedAt == null)
                    .OrderByDescending(c => c.IsPrimary).ThenBy(c => c.CreatedAt)
                    .Select(c => new { c.Name, c.Mobile }).FirstOrDefault(),
            })
            .ToDictionaryAsync(p => p.Id, ct);
        return ranked.Where(x => info.ContainsKey(x.Key)).Select(x =>
        {
            var p = info[x.Key];
            return new SearchCard(p.Id, p.Name, p.IsCustomer, p.IsSupplier && access.CanSeeSuppliers,
                p.Contact?.Mobile ?? p.Phone, p.Contact?.Name, p.Email,
                x.Value.Specs.Select(describe).Take(6).ToList(), x.Value.Reasons.Take(6).ToList(), x.Value.Exact,
                x.Value.Score);
        }).OrderByDescending(c => c.Exact).ThenByDescending(c => c.Score).ThenBy(c => c.Name, StringComparer.Ordinal).ToList();
    }
}
