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
/// بحث «السجل». <see cref="Role"/>: customer أو supplier أو null (الكل).
/// فلاتر الخامة تفرّق بين المطابقة الدقيقة والمواصفات المفتوحة («أي شركة»).
/// </summary>
public sealed record RegistryQuery(
    string? Role = null,
    string? Q = null,
    Guid? MaterialId = null,
    Guid? ManufacturerId = null,
    Guid? GradeId = null,
    Guid? CountryId = null,
    bool Favorites = false,
    PartyStatus? Status = null,
    int Skip = 0,
    int Take = 30);

public static class SpecMatch
{
    /// <summary>مواصفات مسجلة تطابق الفلاتر كلها.</summary>
    public const string Exact = "exact";

    /// <summary>يطابق لأن العميل يقبل أي شركة/Grade لهذه الخامة.</summary>
    public const string Open = "open";
}

public sealed record RegistryItem(
    Guid Id,
    string Name,
    bool IsCustomer,
    bool IsSupplier,
    string? PrimaryPhone,
    string? RepresentativeName,
    Guid? ActivityId,
    Guid? GovernorateId,
    string? Region,
    bool IsFavorite,
    PartySummary? Summary,
    IReadOnlyList<SpecInfo> Specs,
    string? Match,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record HistoryItem(DateTimeOffset At, string? UserName, string Action, string Description);

public sealed class RegistryService(
    IAppDbContext db,
    ICurrentUser user,
    PartyAccess access,
    MaterialSpecs specs,
    PartySummaries summaries,
    TimeProvider clock)
{
    private const int MaxTake = 50;
    private const int MaxStatusScan = 1000;
    private const int MaxSpecsPerItem = 4;

    /// <summary>صف مواصفات موحد من الاهتمامات والمنتجات وبنود الطلبات والتوريدات.</summary>
    private sealed class SpecRow
    {
        public Guid PartyId { get; init; }
        public Guid MaterialId { get; init; }
        public Guid? GradeId { get; init; }
        public Guid? ManufacturerId { get; init; }
        public Guid? OriginId { get; init; }
        public bool Open { get; init; }
    }

    private IQueryable<SpecRow> SpecRows()
    {
        var interests =
            from i in db.CustomerInterests
            join g in db.Grades on i.GradeId equals g.Id into gs
            from g in gs.DefaultIfEmpty()
            select new SpecRow
            {
                PartyId = i.PartyId, MaterialId = i.MaterialId, GradeId = i.GradeId,
                ManufacturerId = g == null ? null : g.ManufacturerId, OriginId = i.OriginCountryId, Open = i.OpenSpec,
            };
        var products =
            from p in db.SupplierProducts
            where p.IsActive
            join g in db.Grades on p.GradeId equals g.Id into gs
            from g in gs.DefaultIfEmpty()
            select new SpecRow
            {
                PartyId = p.PartyId, MaterialId = p.MaterialId, GradeId = p.GradeId,
                ManufacturerId = g == null ? null : g.ManufacturerId, OriginId = p.OriginCountryId, Open = false,
            };
        var orderLines =
            from l in db.OrderLines
            join o in db.Orders on l.OrderId equals o.Id
            where o.DeletedAt == null
            join g in db.Grades on l.GradeId equals g.Id into gs
            from g in gs.DefaultIfEmpty()
            select new SpecRow
            {
                PartyId = o.CustomerId, MaterialId = l.MaterialId, GradeId = l.GradeId,
                ManufacturerId = g == null ? null : g.ManufacturerId, OriginId = l.OriginCountryId, Open = l.OpenSpec,
            };
        var supplyLines =
            from l in db.SupplyLines
            join s in db.Supplies on l.SupplyId equals s.Id
            where s.DeletedAt == null
            join g in db.Grades on l.GradeId equals g.Id into gs
            from g in gs.DefaultIfEmpty()
            select new SpecRow
            {
                PartyId = s.SupplierId, MaterialId = l.MaterialId, GradeId = l.GradeId,
                ManufacturerId = g == null ? null : g.ManufacturerId, OriginId = l.OriginCountryId, Open = false,
            };
        return interests.Concat(products).Concat(orderLines).Concat(supplyLines);
    }

    public async Task<PagedResult<RegistryItem>> ListAsync(RegistryQuery query, CancellationToken ct)
    {
        var customers = user.Has(Permissions.CustomersView) && query.Role is null or "customer";
        var suppliers = user.Has(Permissions.SuppliersView) && query.Role is null or "supplier";
        var parties = db.Parties.AsNoTracking()
            .Where(p => p.DeletedAt == null && ((customers && p.IsCustomer) || (suppliers && p.IsSupplier)));

        if (query.Favorites)
            parties = parties.Where(p => db.UserFavorites.Any(f => f.UserId == user.UserId && f.PartyId == p.Id));

        if (!string.IsNullOrWhiteSpace(query.Q))
            parties = await ApplyTextAsync(parties, query.Q.Trim(), ct);

        // الـ Grade يحدد الخامة والشركة؛ والمواصفات المفتوحة تُحسب فقط عند معرفة الخامة.
        var materialId = query.MaterialId;
        if (query.GradeId is { } gradeId)
            materialId ??= await db.Grades.Where(g => g.Id == gradeId).Select(g => (Guid?)g.MaterialId).FirstOrDefaultAsync(ct);
        var specFilter = materialId is not null || query.ManufacturerId is not null || query.GradeId is not null
            || query.CountryId is not null;
        IQueryable<SpecRow>? exact = null, open = null;
        if (specFilter)
        {
            var rows = SpecRows();
            if (materialId is { } m)
                rows = rows.Where(r => r.MaterialId == m);
            var (maker, grade, country) = (query.ManufacturerId, query.GradeId, query.CountryId);
            exact = rows.Where(r => !r.Open
                && (grade == null || r.GradeId == grade)
                && (maker == null || r.ManufacturerId == maker)
                && (country == null || r.OriginId == country));
            if (materialId is not null)
                open = rows.Where(r => r.Open && (country == null || r.OriginId == null || r.OriginId == country));
            var (e, o) = (exact, open);
            parties = o is null
                ? parties.Where(p => e.Any(r => r.PartyId == p.Id))
                : parties.Where(p => e.Any(r => r.PartyId == p.Id) || o.Any(r => r.PartyId == p.Id));
        }

        var ordered = parties.OrderByDescending(p => p.UpdatedAt).ThenBy(p => p.Id);
        var take = Math.Clamp(query.Take, 1, MaxTake);
        var skip = Math.Max(query.Skip, 0);
        List<Guid> pageIds;
        int total;
        Dictionary<Guid, (PartySummary? Customer, PartySummary? Supplier)>? known = null;
        if (query.Status is { } status)
        {
            var all = await ordered.Take(MaxStatusScan)
                .Select(p => new PartySummaries.Party(p.Id, p.IsCustomer, p.IsSupplier)).ToListAsync(ct);
            known = await summaries.LoadAsync(all, ct);
            var matching = all.Where(p => ViewSummary(known[p.Id], p.IsCustomer, query.Role)?.Status == status)
                .Select(p => p.Id).ToList();
            total = matching.Count;
            pageIds = matching.Skip(skip).Take(take).ToList();
        }
        else
        {
            total = await parties.CountAsync(ct);
            pageIds = await ordered.Skip(skip).Take(take).Select(p => p.Id).ToListAsync(ct);
        }

        var page = await db.Parties.AsNoTracking().Where(p => pageIds.Contains(p.Id))
            .Select(p => new
            {
                p.Id, p.Name, p.IsCustomer, p.IsSupplier, p.CustomerActivityId, p.SupplierActivityId,
                p.GovernorateId, p.Region, p.CreatedAt, p.UpdatedAt,
                Phone = p.Phones.OrderByDescending(ph => ph.IsPrimary).Select(ph => ph.E164).FirstOrDefault(),
                Rep = db.Representatives.Where(r => r.Id == p.RepresentativeId).Select(r => r.Name).FirstOrDefault(),
                Favorite = db.UserFavorites.Any(f => f.UserId == user.UserId && f.PartyId == p.Id),
            })
            .ToDictionaryAsync(p => p.Id, ct);
        known ??= await summaries.LoadAsync(
            page.Values.Select(p => new PartySummaries.Party(p.Id, p.IsCustomer, p.IsSupplier)).ToList(), ct);

        var exactIds = exact is null ? [] : (await exact.Where(r => pageIds.Contains(r.PartyId))
            .Select(r => r.PartyId).Distinct().ToListAsync(ct)).ToHashSet();
        var partySpecs = await PageSpecsAsync(pageIds, query.Role, ct);

        var items = pageIds.Where(page.ContainsKey).Select(id =>
        {
            var p = page[id];
            var asSupplier = query.Role == "supplier" || (query.Role is null && !p.IsCustomer);
            return new RegistryItem(p.Id, p.Name, p.IsCustomer, p.IsSupplier, p.Phone, p.Rep,
                asSupplier ? p.SupplierActivityId : p.CustomerActivityId, p.GovernorateId, p.Region, p.Favorite,
                ViewSummary(known[id], p.IsCustomer, query.Role),
                partySpecs.GetValueOrDefault(id) ?? [],
                !specFilter ? null : exactIds.Contains(id) ? SpecMatch.Exact : SpecMatch.Open,
                p.CreatedAt, p.UpdatedAt);
        }).ToList();
        return new PagedResult<RegistryItem>(items, total);
    }

    private static PartySummary? ViewSummary((PartySummary? Customer, PartySummary? Supplier) s, bool isCustomer,
        string? role) => role switch
        {
            "customer" => s.Customer,
            "supplier" => s.Supplier,
            _ => isCustomer ? s.Customer : s.Supplier,
        };

    /// <summary>الاسم، أو الهاتف (كاملًا أو جزءًا)، أو الخامة/الشركة/Grade/بلد الصنع.</summary>
    private async Task<IQueryable<Party>> ApplyTextAsync(IQueryable<Party> parties, string text, CancellationToken ct)
    {
        var normalized = TextNormalizer.Normalize(text);
        var code = TextNormalizer.NormalizeCode(text);
        var phone = PhoneNumber.Normalize(text);
        var digits = new string(text.Where(char.IsAsciiDigit).ToArray()).TrimStart('0');
        var partialPhone = digits.Length >= 5 && digits.Length == text.Count(c => !char.IsWhiteSpace(c) && c != '+')
            ? digits : null;

        var upper = text.ToUpperInvariant();
        var materialIds = await db.MaterialAliases.Where(a => a.Normalized == normalized).Select(a => a.MaterialId)
            .Union(db.Materials.Where(m => m.Code == upper).Select(m => m.Id))
            .ToListAsync(ct);
        var gradeIds = code.Length >= 2
            ? await db.Grades.Where(g => g.NormalizedCode.Contains(code)).Select(g => g.Id).ToListAsync(ct)
            : [];
        var makerIds = normalized.Length >= 2
            ? await db.Manufacturers.Where(m => m.NormalizedName.Contains(normalized)).Select(m => m.Id).ToListAsync(ct)
            : [];
        var countryIds = normalized.Length >= 2
            ? await db.LookupItems.Where(l => l.Category == LookupCategories.Country && l.NameAr.Contains(text))
                .Select(l => l.Id).ToListAsync(ct)
            : [];

        var rows = SpecRows().Where(r => materialIds.Contains(r.MaterialId)
            || (r.GradeId != null && gradeIds.Contains(r.GradeId.Value))
            || (r.ManufacturerId != null && makerIds.Contains(r.ManufacturerId.Value))
            || (r.OriginId != null && countryIds.Contains(r.OriginId.Value)));
        return parties.Where(p => p.NormalizedName.Contains(normalized)
            || (phone != null && p.Phones.Any(ph => ph.E164 == phone))
            || (partialPhone != null && p.Phones.Any(ph => ph.E164.Contains(partialPhone)))
            || rows.Any(r => r.PartyId == p.Id));
    }

    /// <summary>أهم خامات كل طرف للعرض في البطاقة: اهتمامات العميل أو منتجات المورد.</summary>
    private async Task<Dictionary<Guid, List<SpecInfo>>> PageSpecsAsync(List<Guid> ids, string? role, CancellationToken ct)
    {
        var rows = new List<(Guid PartyId, ResolvedSpec Spec)>();
        if (role is null or "customer")
            rows.AddRange((await db.CustomerInterests.AsNoTracking().Where(i => ids.Contains(i.PartyId))
                    .Select(i => new { i.PartyId, i.MaterialId, i.GradeId, i.OriginCountryId, i.OpenSpec }).ToListAsync(ct))
                .Select(i => (i.PartyId, new ResolvedSpec(i.MaterialId, i.GradeId, i.OriginCountryId, i.OpenSpec))));
        if (role is null or "supplier")
            rows.AddRange((await db.SupplierProducts.AsNoTracking().Where(p => ids.Contains(p.PartyId) && p.IsActive)
                    .Select(p => new { p.PartyId, p.MaterialId, p.GradeId, p.OriginCountryId }).ToListAsync(ct))
                .Select(p => (p.PartyId, new ResolvedSpec(p.MaterialId, p.GradeId, p.OriginCountryId, false))));
        var describe = await specs.DescribeAsync(rows.Select(r => r.Spec), ct);
        return rows.GroupBy(r => r.PartyId)
            .ToDictionary(g => g.Key, g => g.Select(r => describe(r.Spec)).Distinct().Take(MaxSpecsPerItem).ToList());
    }

    public async Task<Result<bool>> SetFavoriteAsync(Guid partyId, bool favorite, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var existing = await db.UserFavorites.FirstOrDefaultAsync(f => f.UserId == user.UserId && f.PartyId == partyId, ct);
        if (favorite && existing is null)
            db.UserFavorites.Add(new UserFavorite { UserId = user.UserId, PartyId = partyId, CreatedAt = clock.GetUtcNow() });
        else if (!favorite && existing is not null)
            db.UserFavorites.Remove(existing);
        else
            return favorite;
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException) when (favorite)
        {
            // إضافة متزامنة من جهاز آخر لنفس المستخدم: النتيجة نفسها.
        }
        return favorite;
    }

    private static readonly Dictionary<string, string> FieldNames = new()
    {
        ["name"] = "الاسم",
        ["phones"] = "أرقام الهاتف",
        ["details"] = "البيانات والعنوان",
        ["representative"] = "المندوب",
        ["customerActivity"] = "نشاط العميل",
        ["supplierActivity"] = "نوع المورد",
        ["interests"] = "الخامات",
    };

    /// <summary>سجل مختصر للتعديلات المهمة على الطرف: من وماذا ومتى.</summary>
    public async Task<Result<IReadOnlyList<HistoryItem>>> HistoryAsync(Guid partyId, int take, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var entries = await (
            from a in db.AuditEntries.AsNoTracking()
            where a.EntityType == "party" && a.EntityId == partyId
            join u in db.Users on a.UserId equals u.Id into us
            from u in us.DefaultIfEmpty()
            orderby a.At descending
            select new { a.At, a.Action, a.Data, User = u == null ? null : u.DisplayName })
            .Take(Math.Clamp(take, 1, 100)).ToListAsync(ct);
        return entries.Select(e => new HistoryItem(e.At, e.User, e.Action, Describe(e.Action, e.Data))).ToList();
    }

    private static string Describe(string action, string? data)
    {
        JsonElement? json = null;
        if (data is not null)
        {
            try
            {
                json = JsonDocument.Parse(data).RootElement;
            }
            catch (JsonException)
            {
            }
        }
        string? Str(string name) =>
            json is { ValueKind: JsonValueKind.Object } o && o.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
                ? v.GetString() : null;
        bool Bool(string name) =>
            json is { ValueKind: JsonValueKind.Object } o && o.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

        return action switch
        {
            "party.created" => "أنشأ السجل",
            "party.updated" => json is { ValueKind: JsonValueKind.Object } o && o.TryGetProperty("fields", out var f)
                    && f.ValueKind == JsonValueKind.Array && f.GetArrayLength() > 0
                ? "عدّل: " + string.Join("، ", f.EnumerateArray().Select(x => FieldNames.GetValueOrDefault(x.GetString() ?? "", x.GetString() ?? "")))
                : "حفظ البيانات دون تغيير",
            "party.role_added" => Bool("addCustomer") ? "أضافه كعميل" : "أضافه كمورد",
            "party.product_added" => $"أضاف منتجًا: {Str("spec")}",
            "party.location_added" => $"أضاف موقعًا: {Str("label")}",
            "party.location_updated" => $"عدّل الموقع: {Str("label")}",
            "party.location_removed" => $"حذف الموقع: {Str("label")}",
            "party.attachment_added" => $"أضاف ملفًا: {Str("name")}",
            "party.attachment_removed" => $"حذف الملف: {Str("name")}",
            _ => action,
        };
    }
}
