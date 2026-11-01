using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Crm;

public sealed record MatchPrice(decimal Price, string Currency, DateOnly QuoteDate, bool Expired);

public sealed record SupplierMatch(
    Guid SupplierId,
    string SupplierName,
    Guid ProductId,
    SpecInfo Product,
    SpecInfo Need,
    int Score,
    IReadOnlyList<string> Reasons,
    MatchPrice? LatestPrice);

public sealed record SupplierMatches(IReadOnlyList<SupplierMatch> Exact, IReadOnlyList<SupplierMatch> Alternatives);

/// <summary>عميل محتمل لمنتج مورد: احتياج العميل المسجل ومنتج المورد الذي يطابقه.</summary>
public sealed record CustomerMatch(
    Guid CustomerId,
    string CustomerName,
    Guid InterestId,
    SpecInfo Product,
    SpecInfo Need,
    int Score,
    IReadOnlyList<string> Reasons);

public sealed record CustomerMatches(IReadOnlyList<CustomerMatch> Exact, IReadOnlyList<CustomerMatch> Alternatives);

/// <summary>
/// مطابقة احتياجات العميل بمنتجات الموردين بقواعد ثابتة قابلة للتفسير (دون ذكاء اصطناعي):
/// التطابق الدقيق = نفس الخامة والشركة والـ Grade (وبلد الصنع إن اشترطه العميل)، والبدائل
/// منفصلة مع سبب الاختلاف. لا يُخترع توافر أو سعر: يُعرض آخر عرض سعر مسجل فقط بتاريخه.
/// النتائج تكشف الموردين، فهي لمن يطّلع عليهم فقط.
/// </summary>
public sealed class MatchingService(IAppDbContext db, ICurrentUser user, PartyAccess access, MaterialSpecs specs,
    TimeProvider clock)
{
    private const int MaxResults = 30;

    public async Task<Result<SupplierMatches>> ForCustomerAsync(Guid customerId, CancellationToken ct)
    {
        if (!access.CanSeeSuppliers)
            return AppError.Forbidden("مطابقة الموردين للإدارة فقط");
        var loaded = await access.LoadVisibleAsync(customerId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (!loaded.Value!.IsCustomer)
            return AppError.Validation("المطابقة تكون لاحتياجات عميل");

        var needs = await db.CustomerInterests.AsNoTracking().Where(i => i.PartyId == customerId).ToListAsync(ct);
        if (needs.Count == 0)
            return new SupplierMatches([], []);
        var materials = needs.Select(n => n.MaterialId).Distinct().ToList();

        var products = await (
            from p in db.SupplierProducts.AsNoTracking()
            join s in db.Parties.AsNoTracking() on p.PartyId equals s.Id
            where p.IsActive && s.IsSupplier && s.DeletedAt == null && materials.Contains(p.MaterialId)
            select new { Product = p, s.Name })
            .ToListAsync(ct);
        var gradeIds = needs.Select(n => n.GradeId).Concat(products.Select(p => p.Product.GradeId))
            .OfType<Guid>().Distinct().ToList();
        var makers = await db.Grades.AsNoTracking().Where(g => gradeIds.Contains(g.Id))
            .ToDictionaryAsync(g => g.Id, g => g.ManufacturerId, ct);
        Guid? Maker(Guid? grade) => grade is { } g && makers.TryGetValue(g, out var m) ? m : null;

        var productIds = products.Select(p => p.Product.Id).ToList();
        var canSeePrices = user.Has(Permissions.PricesView);
        var prices = canSeePrices
            ? (await db.PriceQuotes.AsNoTracking().Where(q => productIds.Contains(q.SupplierProductId)).ToListAsync(ct))
                .GroupBy(q => q.SupplierProductId)
                .ToDictionary(g => g.Key, g => g.OrderByDescending(q => q.QuoteDate).ThenByDescending(q => q.CreatedAt).First())
            : [];
        var supplierIds = products.Select(p => p.Product.PartyId).Distinct().ToList();
        var today = BusinessClock.Today(clock);
        var recent = (await db.Supplies.AsNoTracking()
                .Where(s => supplierIds.Contains(s.SupplierId) && s.Status == SupplyStatus.Received && s.DeletedAt == null)
                .GroupBy(s => s.SupplierId)
                .Select(g => new { g.Key, Last = g.Max(s => s.SupplyDate) })
                .ToListAsync(ct))
            .ToDictionary(x => x.Key, x => x.Last);

        var describe = await specs.DescribeAsync(
            needs.Select(Spec).Concat(products.Select(p => Spec(p.Product))), ct);

        var exact = new List<SupplierMatch>();
        var alternatives = new List<SupplierMatch>();
        foreach (var need in needs)
        {
            var needMaker = Maker(need.GradeId);
            foreach (var row in products.Where(p => p.Product.MaterialId == need.MaterialId))
            {
                var p = row.Product;
                var (score, isExact, reasons) = Evaluate(need, p, needMaker, Maker(p.GradeId));

                MatchPrice? price = null;
                if (prices.TryGetValue(p.Id, out var quote))
                {
                    var expired = quote.ValidUntil is { } until && until < today;
                    price = new MatchPrice(quote.Price, quote.Currency, quote.QuoteDate, expired);
                    if (!expired)
                    {
                        score += 10;
                        reasons.Add($"آخر سعر مسجل بتاريخ {quote.QuoteDate:yyyy-MM-dd}");
                    }
                    else
                    {
                        reasons.Add("آخر سعر مسجل منتهي الصلاحية");
                    }
                }
                if (recent.TryGetValue(p.PartyId, out var last) && last >= today.AddDays(-90))
                {
                    score += 5;
                    reasons.Add($"آخر توريد مستلم منه {last:yyyy-MM-dd}");
                }

                var match = new SupplierMatch(p.PartyId, row.Name, p.Id, describe(Spec(p)), describe(Spec(need)), score,
                    reasons, price);
                (isExact ? exact : alternatives).Add(match);
            }
        }

        static List<SupplierMatch> Rank(IEnumerable<SupplierMatch> items) =>
        [
            .. items.GroupBy(m => (m.ProductId, m.Need))
                .Select(g => g.OrderByDescending(m => m.Score).First())
                .OrderByDescending(m => m.Score).ThenBy(m => m.SupplierName, StringComparer.Ordinal)
                .Take(MaxResults),
        ];
        var exactRanked = Rank(exact);
        var exactProducts = exactRanked.Select(m => m.ProductId).ToHashSet();
        return new SupplierMatches(exactRanked, Rank(alternatives.Where(a => !exactProducts.Contains(a.ProductId))));
    }

    /// <summary>
    /// قاعدة المطابقة الواحدة لاحتياج عميل ومنتج مورد من نفس الخامة، مستخدمة في الاتجاهين
    /// (الموردون المناسبون للعميل، والعملاء المحتملون للمورد) فتبقى النتائج متسقة. الدقيق فقط:
    /// نفس الـ Grade (وبلد الصنع إن اشترطه العميل) أو عميل يقبل أي شركة؛ Grade مختلف بديل دائمًا.
    /// </summary>
    private static (int Score, bool Exact, List<string> Reasons) Evaluate(CustomerInterest need, SupplierProduct p,
        Guid? needMaker, Guid? productMaker)
    {
        var reasons = new List<string>();
        if (need.GradeId is { } grade && p.GradeId == grade)
        {
            if (need.OriginCountryId is { } origin && p.OriginCountryId is { } offered && offered != origin)
            {
                reasons.Add("نفس الـ Grade لكن بلد الصنع مختلف عن المطلوب");
                return (60, false, reasons);
            }
            reasons.Add("نفس الخامة والشركة المصنّعة والـ Grade");
            if (need.OriginCountryId is not null)
                reasons.Add(p.OriginCountryId is null ? "بلد الصنع غير مسجل لدى المورد" : "نفس بلد الصنع المطلوب");
            return (100, true, reasons);
        }
        if (need.OpenSpec)
        {
            reasons.Add("العميل يقبل أي شركة لهذه الخامة");
            return (80, true, reasons);
        }
        if (need.GradeId is null)
        {
            reasons.Add("العميل حدد نوع الخامة فقط دون Grade");
            return (40, false, reasons);
        }
        if (needMaker is not null && productMaker == needMaker)
        {
            reasons.Add("نفس الشركة المصنّعة بـ Grade مختلف");
            return (50, false, reasons);
        }
        reasons.Add("نفس الخامة من شركة أو Grade مختلف");
        return (30, false, reasons);
    }

    /// <summary>
    /// العملاء المحتملون لمنتجات مورد: نفس قاعدة المطابقة بالاتجاه العكسي. ملف المورد لمن يطّلع على
    /// الموردين فقط، والعملاء في النتائج هم من يراهم المستخدم بصلاحياته الحالية فقط.
    /// </summary>
    public async Task<Result<CustomerMatches>> ForSupplierAsync(Guid supplierId, CancellationToken ct)
    {
        if (!access.CanSeeSuppliers)
            return AppError.Forbidden("مطابقة الموردين للإدارة فقط");
        var loaded = await access.LoadVisibleAsync(supplierId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (!loaded.Value!.IsSupplier)
            return AppError.Validation("المطابقة تكون لمنتجات مورد");

        var products = await db.SupplierProducts.AsNoTracking().Where(p => p.PartyId == supplierId && p.IsActive)
            .ToListAsync(ct);
        if (products.Count == 0)
            return new CustomerMatches([], []);
        var materials = products.Select(p => p.MaterialId).Distinct().ToList();

        var customers = access.VisibleAs(db.Parties.AsNoTracking().Where(c => c.DeletedAt == null), true, false)
            .Where(c => c.IsCustomer && c.Id != supplierId);
        var needs = await (
                from i in db.CustomerInterests.AsNoTracking()
                join c in customers on i.PartyId equals c.Id
                where materials.Contains(i.MaterialId)
                select new { Need = i, c.Name })
            .ToListAsync(ct);

        var gradeIds = needs.Select(n => n.Need.GradeId).Concat(products.Select(p => p.GradeId))
            .OfType<Guid>().Distinct().ToList();
        var makers = await db.Grades.AsNoTracking().Where(g => gradeIds.Contains(g.Id))
            .ToDictionaryAsync(g => g.Id, g => g.ManufacturerId, ct);
        Guid? Maker(Guid? grade) => grade is { } g && makers.TryGetValue(g, out var m) ? m : null;
        var describe = await specs.DescribeAsync(
            needs.Select(n => Spec(n.Need)).Concat(products.Select(Spec)), ct);

        var exact = new List<CustomerMatch>();
        var alternatives = new List<CustomerMatch>();
        foreach (var row in needs)
        {
            var need = row.Need;
            foreach (var p in products.Where(p => p.MaterialId == need.MaterialId))
            {
                var (score, isExact, reasons) = Evaluate(need, p, Maker(need.GradeId), Maker(p.GradeId));
                var match = new CustomerMatch(need.PartyId, row.Name, need.Id, describe(Spec(p)), describe(Spec(need)),
                    score, reasons);
                (isExact ? exact : alternatives).Add(match);
            }
        }

        // بطاقة واحدة لكل احتياج عميل (أفضل منتج يطابقه)، والاحتياج المطابق تمامًا لا يتكرر في البدائل.
        static List<CustomerMatch> Rank(IEnumerable<CustomerMatch> items) =>
        [
            .. items.GroupBy(m => m.InterestId)
                .Select(g => g.OrderByDescending(m => m.Score).First())
                .OrderByDescending(m => m.Score).ThenBy(m => m.CustomerName, StringComparer.Ordinal)
                .Take(MaxResults),
        ];
        var exactRanked = Rank(exact);
        var exactNeeds = exactRanked.Select(m => m.InterestId).ToHashSet();
        return new CustomerMatches(exactRanked, Rank(alternatives.Where(a => !exactNeeds.Contains(a.InterestId))));
    }

    private static ResolvedSpec Spec(CustomerInterest i) => new(i.MaterialId, i.GradeId, i.OriginCountryId, i.OpenSpec);

    private static ResolvedSpec Spec(SupplierProduct p) => new(p.MaterialId, p.GradeId, p.OriginCountryId, false);
}
