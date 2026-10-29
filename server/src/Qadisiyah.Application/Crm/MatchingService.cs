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
                var reasons = new List<string>();
                int score;
                var isExact = false;
                if (need.GradeId is { } grade && p.GradeId == grade)
                {
                    if (need.OriginCountryId is { } origin && p.OriginCountryId is { } offered && offered != origin)
                    {
                        score = 60;
                        reasons.Add("نفس الـ Grade لكن بلد الصنع مختلف عن المطلوب");
                    }
                    else
                    {
                        score = 100;
                        isExact = true;
                        reasons.Add("نفس الخامة والشركة المصنّعة والـ Grade");
                        if (need.OriginCountryId is not null)
                            reasons.Add(p.OriginCountryId is null ? "بلد الصنع غير مسجل لدى المورد" : "نفس بلد الصنع المطلوب");
                    }
                }
                else if (need.OpenSpec)
                {
                    score = 80;
                    isExact = true;
                    reasons.Add("العميل يقبل أي شركة لهذه الخامة");
                }
                else if (need.GradeId is null)
                {
                    score = 40;
                    reasons.Add("العميل حدد نوع الخامة فقط دون Grade");
                }
                else if (needMaker is not null && Maker(p.GradeId) == needMaker)
                {
                    score = 50;
                    reasons.Add("نفس الشركة المصنّعة بـ Grade مختلف");
                }
                else
                {
                    score = 30;
                    reasons.Add("نفس الخامة من شركة أو Grade مختلف");
                }

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

    private static ResolvedSpec Spec(CustomerInterest i) => new(i.MaterialId, i.GradeId, i.OriginCountryId, i.OpenSpec);

    private static ResolvedSpec Spec(SupplierProduct p) => new(p.MaterialId, p.GradeId, p.OriginCountryId, false);
}
