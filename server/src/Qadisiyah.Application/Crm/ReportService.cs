using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Crm;

public sealed record RepActivity(string Representative, int NewCustomers, int Contacts, int Orders, decimal OrdersKg);

public sealed record MaterialDemand(string Spec, int Customers, int? Suppliers);

public sealed record DuplicateGroup(string Name, IReadOnlyList<Guid> PartyIds, IReadOnlyList<string> Names);

public sealed record DataQuality(int MissingActivity, int MissingGovernorate, int WithoutLocation, int WithoutContacts,
    IReadOnlyList<DuplicateGroup> PossibleDuplicates);

public sealed record ReportSummary(
    DateOnly From,
    DateOnly To,
    int OverdueFollowUps,
    int TodayFollowUps,
    IReadOnlyList<RepActivity> Representatives,
    IReadOnlyList<MaterialDemand> Materials,
    DataQuality? Quality);

/// <summary>
/// تقارير المتابعات ونشاط المندوبين والخامات وجودة البيانات، كلها داخل نطاق ما يراه المستخدم:
/// المندوب يرى أرقام عملائه فقط، ولا أعداد موردين ولا تكرارات لغير «المطلعين على الكل».
/// </summary>
public sealed partial class ReportService(IAppDbContext db, ICurrentUser user, PartyAccess access, FollowUpService followUps,
    MaterialSpecs specs, PartySummaries summaries, TimeProvider clock)
{
    public async Task<Result<ReportSummary>> SummaryAsync(DateOnly? from, DateOnly? to, CancellationToken ct)
    {
        if (!user.Has(Permissions.ReportsView))
            return AppError.Forbidden();
        var end = to ?? BusinessClock.Today(clock);
        var start = from ?? end.AddDays(-30);
        if (start > end)
            return AppError.Validation("تاريخ البداية بعد تاريخ النهاية");
        var startAt = new DateTimeOffset(start.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
        var endAt = new DateTimeOffset(end.AddDays(1).ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);

        var due = await followUps.ListAsync(0, ct);
        var customers = access.VisibleAs(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null), true, false);

        var reps = await db.Representatives.AsNoTracking().ToDictionaryAsync(r => r.Id, r => r.Name, ct);
        string RepName(Guid? id) => id is { } v && reps.TryGetValue(v, out var n) ? n : "غير محدد";

        var newCustomers = await customers.Where(p => p.CreatedAt >= startAt && p.CreatedAt < endAt)
            .GroupBy(p => p.RepresentativeId).Select(g => new { g.Key, Count = g.Count() }).ToListAsync(ct);
        var contacts = await (
                from i in db.Interactions.AsNoTracking()
                join p in customers on i.PartyId equals p.Id
                where i.OccurredAt >= startAt && i.OccurredAt < endAt && i.DeletedAt == null
                group i by p.RepresentativeId into g
                select new { g.Key, Count = g.Count() })
            .ToListAsync(ct);
        var orders = await (
                from o in db.Orders.AsNoTracking()
                join p in customers on o.CustomerId equals p.Id
                where o.OrderDate >= start && o.OrderDate <= end && o.DeletedAt == null
                group o by p.RepresentativeId into g
                select new { g.Key, Count = g.Count(), Kg = g.Sum(o => o.Lines.Sum(l => l.QuantityKg)) })
            .ToListAsync(ct);
        var repIds = newCustomers.Select(x => x.Key).Concat(contacts.Select(x => x.Key)).Concat(orders.Select(x => x.Key))
            .Distinct();
        var repRows = repIds.Select(id => new RepActivity(RepName(id),
                newCustomers.FirstOrDefault(x => x.Key == id)?.Count ?? 0,
                contacts.FirstOrDefault(x => x.Key == id)?.Count ?? 0,
                orders.FirstOrDefault(x => x.Key == id)?.Count ?? 0,
                orders.FirstOrDefault(x => x.Key == id)?.Kg ?? 0))
            .OrderByDescending(r => r.Contacts + r.Orders).ToList();

        // الطلب على الخامات من اهتمامات العملاء الظاهرين، والعرض لدى الموردين لمن يراهم فقط.
        var demand = await (
                from i in db.CustomerInterests.AsNoTracking()
                join p in customers on i.PartyId equals p.Id
                group i by new { i.MaterialId, i.GradeId } into g
                select new { g.Key.MaterialId, g.Key.GradeId, Count = g.Select(x => x.PartyId).Distinct().Count() })
            .OrderByDescending(x => x.Count).Take(15).ToListAsync(ct);
        Dictionary<(Guid, Guid?), int> supply = [];
        if (access.CanSeeSuppliers)
        {
            var materialIds = demand.Select(d => d.MaterialId).ToList();
            supply = (await (
                    from sp in db.SupplierProducts.AsNoTracking()
                    join s in db.Parties.AsNoTracking() on sp.PartyId equals s.Id
                    where sp.IsActive && s.DeletedAt == null && materialIds.Contains(sp.MaterialId)
                    select new { sp.MaterialId, sp.GradeId, sp.PartyId })
                .ToListAsync(ct))
                .GroupBy(x => (x.MaterialId, x.GradeId))
                .ToDictionary(g => g.Key, g => g.Select(x => x.PartyId).Distinct().Count());
        }
        var describe = await specs.DescribeAsync(demand.Select(d => new ResolvedSpec(d.MaterialId, d.GradeId, null, false)), ct);
        var materials = demand.Select(d => new MaterialDemand(
            PartyService.SpecLabel(describe(new ResolvedSpec(d.MaterialId, d.GradeId, null, false))),
            d.Count,
            access.CanSeeSuppliers ? supply.GetValueOrDefault((d.MaterialId, d.GradeId)) : null)).ToList();

        return new ReportSummary(start, end, due.Count(f => f.Status == "overdue"), due.Count(f => f.Status == "today"),
            repRows, materials, await QualityAsync(ct));
    }

    /// <summary>جودة البيانات والتكرارات لمن يرى الكل فقط.</summary>
    private async Task<DataQuality?> QualityAsync(CancellationToken ct)
    {
        DataQuality? quality = null;
        if (access.ViewAll)
        {
            var all = db.Parties.AsNoTracking().Where(p => p.DeletedAt == null);
            var names = await all.Select(p => new { p.Id, p.Name }).Take(20_000).ToListAsync(ct);
            var duplicates = names.GroupBy(p => PartyService.CoreName(p.Name))
                .Where(g => g.Key.Length > 0 && g.Count() > 1)
                .OrderByDescending(g => g.Count()).Take(20)
                .Select(g => new DuplicateGroup(g.Key, g.Select(x => x.Id).ToList(), g.Select(x => x.Name).ToList()))
                .ToList();
            quality = new DataQuality(
                await all.CountAsync(p => (p.IsCustomer && p.CustomerActivityId == null)
                    || (p.IsSupplier && p.SupplierActivityId == null), ct),
                await all.CountAsync(p => p.GovernorateId == null, ct),
                await all.CountAsync(p => !db.PartyLocations.Any(l => l.PartyId == p.Id && l.DeletedAt == null), ct),
                await all.CountAsync(p => !db.PartyContacts.Any(c => c.PartyId == p.Id && c.DeletedAt == null), ct),
                duplicates);
        }
        return quality;
    }
}
