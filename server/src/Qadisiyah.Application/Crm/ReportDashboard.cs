using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Crm;

/// <summary>فلاتر لوحة التقارير؛ الافتراضي الشهر الحالي حتى اليوم.</summary>
public sealed record DashboardFilter(DateOnly? From = null, DateOnly? To = null, Guid? RepresentativeId = null,
    Guid? MaterialId = null, Guid? GradeId = null, Guid? CustomerId = null);

/// <param name="ValueAvailable">قيمة المبيعات غير متاحة: سطور الطلبات لا تحمل سعرًا بعد.</param>
/// <param name="ConversionRate">المكتمل ÷ (المكتمل + الملغى) للطلبات المنتهية في الفترة.</param>
public sealed record DashboardKpis(int CompletedOrders, decimal CompletedKg, int OpenOrders, decimal OpenKg,
    int CancelledOrders, decimal CancelledKg, int ActiveCustomers, int NewCustomers, int Contacts,
    decimal? ConversionRate, bool ValueAvailable);

public sealed record RankRow(Guid? Id, string Label, int Orders, decimal Kg, string? Extra = null);

public sealed record StageRow(string Stage, int Orders, decimal Kg);

public sealed record TrendPoint(string Month, int Orders, decimal Kg);

/// <param name="Suppliers">عدد الموردين المتاحين لمن يرى الموردين فقط.</param>
public sealed record DemandRow(string Material, int DemandCustomers, decimal SoldKg, int? Suppliers);

public sealed record CustomerActivity(int New, int Active, int NeedsFollowUp, int Stopped);

public sealed record ReportDashboard(
    DateOnly From,
    DateOnly To,
    DashboardKpis Kpis,
    IReadOnlyList<StageRow> Pipeline,
    IReadOnlyList<RankRow> Materials,
    IReadOnlyList<RankRow> Grades,
    IReadOnlyList<RankRow> Customers,
    IReadOnlyList<RankRow> Representatives,
    IReadOnlyList<RankRow>? Suppliers,
    IReadOnlyList<TrendPoint> Trend,
    IReadOnlyList<DemandRow> Demand,
    CustomerActivity Activity,
    IReadOnlyList<RankRow> Dormant,
    int OverdueFollowUps,
    int TodayFollowUps,
    int IncompleteRecords,
    DataQuality? Quality);

/// <summary>
/// لوحة التقارير من الطلبات المسجلة: المكتمل مبيعات محققة، والمفتوح والملغى كلٌ منفصل.
/// كل الأرقام من العملاء الظاهرين للمستخدم فقط (لا تكشف المجاميع سجلات مخفية)، والموردون
/// لمن يراهم فقط.
/// </summary>
public sealed partial class ReportService
{
    private const int TopN = 10;

    private static readonly OrderStage[] OpenStages =
        [OrderStage.Inquiry, OrderStage.Quotation, OrderStage.Confirmed, OrderStage.InProgress];

    public async Task<Result<ReportDashboard>> DashboardAsync(DashboardFilter filter, CancellationToken ct)
    {
        if (!user.Has(Permissions.ReportsView))
            return AppError.Forbidden();
        var today = BusinessClock.Today(clock);
        var end = filter.To ?? today;
        var start = filter.From ?? new DateOnly(end.Year, end.Month, 1);
        if (start > end)
            return AppError.Validation("تاريخ البداية بعد تاريخ النهاية");
        if (end.DayNumber - start.DayNumber > 3660)
            return AppError.Validation("الفترة أطول من 10 سنوات");
        var startAt = new DateTimeOffset(start.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
        var endAt = new DateTimeOffset(end.AddDays(1).ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
        var trendStart = new DateOnly(end.Year, end.Month, 1).AddMonths(-5);
        var loadFrom = trendStart < start ? trendStart : start;

        var customers = access.VisibleAs(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null), true, false);
        if (filter.CustomerId is { } customerId)
            customers = customers.Where(p => p.Id == customerId);
        var repId = filter.RepresentativeId;

        // سطور الطلبات للفترة والاتجاه (6 أشهر) دفعة واحدة.
        var lines = await (
                from o in db.Orders.AsNoTracking()
                join p in customers on o.CustomerId equals p.Id
                from l in o.Lines
                where o.DeletedAt == null && o.OrderDate >= loadFrom && o.OrderDate <= end
                    && (repId == null || (o.RepresentativeId ?? p.RepresentativeId) == repId)
                    && (filter.MaterialId == null || l.MaterialId == filter.MaterialId)
                    && (filter.GradeId == null || l.GradeId == filter.GradeId)
                select new
                {
                    OrderId = o.Id, o.OrderDate, o.Stage, o.CustomerId, CustomerName = p.Name,
                    Rep = o.RepresentativeId ?? p.RepresentativeId, l.MaterialId, l.GradeId, l.QuantityKg,
                })
            .ToListAsync(ct);
        var period = lines.Where(l => l.OrderDate >= start).ToList();
        var completed = period.Where(l => l.Stage == OrderStage.Completed).ToList();
        var open = period.Where(l => OpenStages.Contains(l.Stage)).ToList();
        var cancelled = period.Where(l => l.Stage == OrderStage.Cancelled).ToList();
        static int Orders<T>(IEnumerable<T> rows, Func<T, Guid> id) => rows.Select(id).Distinct().Count();

        var newCustomers = await customers.CountAsync(p => p.CreatedAt >= startAt && p.CreatedAt < endAt
            && (repId == null || p.RepresentativeId == repId), ct);
        var contacts = await (
                from i in db.Interactions.AsNoTracking()
                join p in customers on i.PartyId equals p.Id
                where i.DeletedAt == null && i.OccurredAt >= startAt && i.OccurredAt < endAt
                    && (repId == null || p.RepresentativeId == repId)
                select i.Id)
            .CountAsync(ct);
        var completedOrders = Orders(completed, l => l.OrderId);
        var cancelledOrders = Orders(cancelled, l => l.OrderId);
        var kpis = new DashboardKpis(
            completedOrders, completed.Sum(l => l.QuantityKg),
            Orders(open, l => l.OrderId), open.Sum(l => l.QuantityKg),
            cancelledOrders, cancelled.Sum(l => l.QuantityKg),
            completed.Select(l => l.CustomerId).Distinct().Count(), newCustomers, contacts,
            completedOrders + cancelledOrders == 0
                ? null
                : Math.Round((decimal)completedOrders / (completedOrders + cancelledOrders), 3),
            ValueAvailable: false);

        var pipeline = Enum.GetValues<OrderStage>()
            .Select(s => new StageRow(s.ToString(), Orders(period.Where(l => l.Stage == s), l => l.OrderId),
                period.Where(l => l.Stage == s).Sum(l => l.QuantityKg)))
            .ToList();

        // أسماء الخامات والـ Grades والمندوبين.
        var materialNames = await db.Materials.AsNoTracking().ToDictionaryAsync(m => m.Id, m => m.Code, ct);
        var gradeIds = completed.Where(l => l.GradeId != null).Select(l => l.GradeId!.Value).Distinct().ToList();
        var describe = await specs.DescribeAsync(
            completed.Where(l => l.GradeId != null).Select(l => new ResolvedSpec(l.MaterialId, l.GradeId, null, false))
                .Distinct(), ct);
        var reps = await db.Representatives.AsNoTracking().ToDictionaryAsync(r => r.Id, r => r.Name, ct);

        List<RankRow> Rank<TKey>(IEnumerable<(TKey Key, Guid OrderId, decimal Kg)> rows, Func<TKey, Guid?> id,
            Func<TKey, string> label, Func<TKey, string?>? extra = null) =>
            rows.GroupBy(r => r.Key)
                .Select(g => new RankRow(id(g.Key), label(g.Key), g.Select(x => x.OrderId).Distinct().Count(),
                    g.Sum(x => x.Kg), extra?.Invoke(g.Key)))
                .OrderByDescending(r => r.Kg).ThenByDescending(r => r.Orders).Take(TopN).ToList();

        var materials = Rank(completed.Select(l => (l.MaterialId, l.OrderId, l.QuantityKg)), k => k,
            k => materialNames.GetValueOrDefault(k, "?"));
        var grades = Rank(completed.Where(l => l.GradeId != null)
                .Select(l => ((l.MaterialId, Grade: l.GradeId!.Value), l.OrderId, l.QuantityKg)),
            k => k.Grade, k => PartyService.SpecLabel(describe(new ResolvedSpec(k.MaterialId, k.Grade, null, false))));
        var lastOrder = completed.GroupBy(l => l.CustomerId).ToDictionary(g => g.Key, g => g.Max(x => x.OrderDate));
        var topCustomers = Rank(completed.Select(l => ((l.CustomerId, l.CustomerName), l.OrderId, l.QuantityKg)),
            k => k.CustomerId, k => k.CustomerName,
            k => "آخر طلب " + lastOrder[k.CustomerId].ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
        var repContacts = await (
                from i in db.Interactions.AsNoTracking()
                join p in customers on i.PartyId equals p.Id
                where i.DeletedAt == null && i.OccurredAt >= startAt && i.OccurredAt < endAt
                group i by p.RepresentativeId into g
                select new { g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.Key ?? Guid.Empty, x => x.Count, ct);
        var representatives = Rank(completed.Select(l => (l.Rep ?? Guid.Empty, l.OrderId, l.QuantityKg)),
            k => k == Guid.Empty ? null : k, k => reps.GetValueOrDefault(k, "غير محدد"),
            k => $"{repContacts.GetValueOrDefault(k)} تواصل");

        List<RankRow>? suppliers = null;
        if (access.CanSeeSuppliers && filter.CustomerId is null)
        {
            var received = await (
                    from s in db.Supplies.AsNoTracking()
                    join p in db.Parties.AsNoTracking() on s.SupplierId equals p.Id
                    from l in s.Lines
                    where s.DeletedAt == null && p.DeletedAt == null && s.Status == SupplyStatus.Received
                        && s.SupplyDate >= start && s.SupplyDate <= end
                        && (filter.MaterialId == null || l.MaterialId == filter.MaterialId)
                        && (filter.GradeId == null || l.GradeId == filter.GradeId)
                    select new { s.Id, s.SupplierId, p.Name, l.QuantityKg })
                .ToListAsync(ct);
            suppliers = Rank(received.Select(r => ((r.SupplierId, r.Name), r.Id, r.QuantityKg)), k => k.SupplierId,
                k => k.Name);
        }

        var trend = Enumerable.Range(0, 6).Select(i => trendStart.AddMonths(i)).Select(m =>
        {
            var month = lines.Where(l => l.Stage == OrderStage.Completed && l.OrderDate.Year == m.Year
                && l.OrderDate.Month == m.Month).ToList();
            return new TrendPoint(m.ToString("yyyy-MM", CultureInfo.InvariantCulture),
                Orders(month, l => l.OrderId), month.Sum(l => l.QuantityKg));
        }).ToList();

        // الطلب (اهتمامات العملاء الظاهرين) مقابل المبيعات المكتملة لكل خامة.
        var interest = await (
                from i in db.CustomerInterests.AsNoTracking()
                join p in customers on i.PartyId equals p.Id
                where (repId == null || p.RepresentativeId == repId)
                    && (filter.MaterialId == null || i.MaterialId == filter.MaterialId)
                    && (filter.GradeId == null || i.GradeId == filter.GradeId || i.OpenSpec)
                group i by i.MaterialId into g
                select new { MaterialId = g.Key, Count = g.Select(x => x.PartyId).Distinct().Count() })
            .ToListAsync(ct);
        var soldByMaterial = completed.GroupBy(l => l.MaterialId).ToDictionary(g => g.Key, g => g.Sum(x => x.QuantityKg));
        Dictionary<Guid, int> supplierCounts = [];
        if (access.CanSeeSuppliers)
            supplierCounts = await (
                    from sp in db.SupplierProducts.AsNoTracking()
                    join p in db.Parties.AsNoTracking() on sp.PartyId equals p.Id
                    where sp.IsActive && p.DeletedAt == null
                    group sp by sp.MaterialId into g
                    select new { g.Key, Count = g.Select(x => x.PartyId).Distinct().Count() })
                .ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var demand = interest.Select(x => x.MaterialId).Union(soldByMaterial.Keys)
            .Select(id => new DemandRow(materialNames.GetValueOrDefault(id, "?"),
                interest.FirstOrDefault(x => x.MaterialId == id)?.Count ?? 0, soldByMaterial.GetValueOrDefault(id),
                access.CanSeeSuppliers ? supplierCounts.GetValueOrDefault(id) : null))
            .OrderByDescending(d => d.DemandCustomers).ThenByDescending(d => d.SoldKg).Take(15).ToList();

        // نشاط العملاء (نشط/خامل) بنفس قواعد حالة العميل في الملف.
        var scoped = await customers.Where(p => repId == null || p.RepresentativeId == repId)
            .Select(p => new { p.Id, p.Name }).Take(20_000).ToListAsync(ct);
        var states = await summaries.LoadAsync(
            scoped.Select(p => new PartySummaries.Party(p.Id, true, false)).ToList(), ct);
        var activity = new CustomerActivity(
            states.Values.Count(s => s.Customer?.Status == PartyStatus.New),
            states.Values.Count(s => s.Customer?.Status == PartyStatus.Active),
            states.Values.Count(s => s.Customer?.Status == PartyStatus.NeedsFollowUp),
            states.Values.Count(s => s.Customer?.Status == PartyStatus.Stopped));
        var dormant = scoped
            .Where(p => states[p.Id].Customer is { Status: PartyStatus.Stopped or PartyStatus.NeedsFollowUp, LastDealDate: not null })
            .Select(p => (p, s: states[p.Id].Customer!))
            .OrderBy(x => x.s.LastDealDate).Take(TopN)
            .Select(x => new RankRow(x.p.Id, x.p.Name, 0, x.s.LastDealQuantityKg ?? 0,
                "آخر تعامل " + x.s.LastDealDate!.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)))
            .ToList();

        var due = await followUps.ListAsync(0, ct);
        var incomplete = await access.Visible(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null))
            .CountAsync(p => p.NameMissing || !p.Phones.Any() || (!p.IsCustomer && !p.IsSupplier), ct);

        return new ReportDashboard(start, end, kpis, pipeline, materials, grades, topCustomers, representatives,
            suppliers, trend, demand, activity, dormant,
            due.Count(f => f.Status == "overdue"), due.Count(f => f.Status == "today"), incomplete,
            await QualityAsync(ct));
    }

    private static readonly Dictionary<string, string> StageNames = new()
    {
        [nameof(OrderStage.Inquiry)] = "استفسار",
        [nameof(OrderStage.Quotation)] = "عرض سعر",
        [nameof(OrderStage.Confirmed)] = "مؤكد",
        [nameof(OrderStage.InProgress)] = "قيد التنفيذ",
        [nameof(OrderStage.Completed)] = "مكتمل",
        [nameof(OrderStage.Cancelled)] = "ملغى",
    };

    /// <summary>اللوحة إلى Excel بأقسام متتالية في ورقة واحدة؛ لمن يملك «استخراج التقارير» فقط.</summary>
    public async Task<Result<(byte[] Content, string FileName)>> DashboardExcelAsync(DashboardFilter filter,
        IReadOnlyCollection<string>? sections, CancellationToken ct)
    {
        if (!user.Has(Permissions.ReportsExport))
            return AppError.Forbidden("تصدير التقارير غير مسموح لهذا المستخدم");
        var loaded = await DashboardAsync(filter, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var d = loaded.Value!;
        bool Want(string key) => sections is not { Count: > 0 } || sections.Contains(key);
        var rows = new List<IReadOnlyList<object?>>();
        void Section(string title, IEnumerable<IReadOnlyList<object?>> items)
        {
            rows.Add([title]);
            rows.AddRange(items);
            rows.Add([]);
        }

        static IEnumerable<IReadOnlyList<object?>> Ranked(IEnumerable<RankRow> r) =>
            r.Select((x, i) => (IReadOnlyList<object?>)[i + 1, x.Label, x.Orders, x.Kg, x.Extra]);

        rows.Add(["الفترة", $"{d.From:yyyy-MM-dd} — {d.To:yyyy-MM-dd}"]);
        rows.Add(["قيمة المبيعات", "غير متاحة (الطلبات لا تحمل أسعارًا)"]);
        rows.Add([]);
        if (Want("kpis"))
            Section("المؤشرات",
            [
                ["", "طلبات مكتملة (مبيعات محققة)", d.Kpis.CompletedOrders, d.Kpis.CompletedKg],
                ["", "طلبات مفتوحة", d.Kpis.OpenOrders, d.Kpis.OpenKg],
                ["", "طلبات ملغاة", d.Kpis.CancelledOrders, d.Kpis.CancelledKg],
                ["", "عملاء اشتروا", d.Kpis.ActiveCustomers],
                ["", "عملاء جدد", d.Kpis.NewCustomers],
                ["", "تواصلات", d.Kpis.Contacts],
                ["", "نسبة التحويل", d.Kpis.ConversionRate is { } c ? $"{c * 100:0.#}%" : "—"],
            ]);
        if (Want("pipeline"))
            Section("مراحل الطلبات", d.Pipeline.Select(p =>
                (IReadOnlyList<object?>)["", StageNames.GetValueOrDefault(p.Stage, p.Stage), p.Orders, p.Kg]));
        if (Want("materials"))
            Section("أعلى الخامات (كجم مكتمل)", Ranked(d.Materials));
        if (Want("grades"))
            Section("أعلى الـ Grades", Ranked(d.Grades));
        if (Want("customers"))
            Section("أعلى العملاء", Ranked(d.Customers));
        if (Want("representatives"))
            Section("المندوبون والمديرون", Ranked(d.Representatives));
        if (Want("suppliers") && d.Suppliers is not null)
            Section("الموردون (توريد مستلم)", Ranked(d.Suppliers));
        if (Want("trend"))
            Section("الاتجاه الشهري (مكتمل)", d.Trend.Select(t => (IReadOnlyList<object?>)["", t.Month, t.Orders, t.Kg]));
        if (Want("demand"))
            Section("الطلب مقابل المبيعات", d.Demand.Select(x =>
                (IReadOnlyList<object?>)["", x.Material, x.DemandCustomers, x.SoldKg, x.Suppliers]));
        if (Want("activity"))
            Section("نشاط العملاء",
            [
                ["", "جديد", d.Activity.New], ["", "نشط", d.Activity.Active],
                ["", "يحتاج متابعة", d.Activity.NeedsFollowUp], ["", "متوقف", d.Activity.Stopped],
            ]);
        if (Want("dormant"))
            Section("عملاء خاملون", Ranked(d.Dormant));
        if (Want("followUps"))
            Section("المتابعات", [["", "متأخرة", d.OverdueFollowUps], ["", "اليوم", d.TodayFollowUps]]);
        if (Want("quality"))
        {
            List<IReadOnlyList<object?>> quality = [["", "سجلات تحتاج استكمال", d.IncompleteRecords]];
            if (d.Quality is { } q)
                quality.AddRange(
                [
                    ["", "بدون نوع نشاط", q.MissingActivity], ["", "بدون محافظة", q.MissingGovernorate],
                    ["", "بدون موقع", q.WithoutLocation], ["", "بدون جهات اتصال", q.WithoutContacts],
                    ["", "تكرارات محتملة", q.PossibleDuplicates.Count],
                ]);
            Section("جودة البيانات", quality);
        }

        db.Audit(user, clock, "export.report", "report", Guid.Empty,
            new { d.From, d.To, filter.RepresentativeId, filter.MaterialId, filter.GradeId, filter.CustomerId, sections });
        await db.SaveChangesAsync(ct);
        var content = XlsxWriter.Write("التقرير", ["#", "البند", "عدد", "الكمية (كجم)", "ملاحظة"], rows);
        return (content, $"report-{d.From:yyyyMMdd}-{d.To:yyyyMMdd}.xlsx");
    }
}
