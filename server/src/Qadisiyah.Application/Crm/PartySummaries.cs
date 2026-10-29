using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

/// <summary>
/// يحسب ملخص كل طرف (الحالة، آخر تعامل، آخر تواصل، المتابعة القادمة) من
/// الأحداث المسجلة فقط، لعدة أطراف في استعلامات قليلة. يُستخدم في الملف وفي السجل.
/// </summary>
public sealed class PartySummaries(IAppDbContext db, TimeProvider clock)
{
    public sealed record Party(Guid Id, bool IsCustomer, bool IsSupplier);

    public async Task<Dictionary<Guid, (PartySummary? Customer, PartySummary? Supplier)>> LoadAsync(
        IReadOnlyCollection<Party> parties, CancellationToken ct)
    {
        var ids = parties.Select(p => p.Id).ToList();
        var rules = await LoadStatusRulesAsync(ct);
        var now = clock.GetUtcNow();
        var today = DateOnly.FromDateTime(now.UtcDateTime);

        var interactions = (await db.Interactions.AsNoTracking()
                .Where(i => ids.Contains(i.PartyId) && i.DeletedAt == null)
                .Select(i => new { i.PartyId, i.OccurredAt, i.NextFollowUpAt, i.FollowUpDone })
                .ToListAsync(ct))
            .ToLookup(i => i.PartyId);
        var orders = (await db.Orders.AsNoTracking()
                .Where(o => ids.Contains(o.CustomerId) && o.DeletedAt == null
                    && (o.Stage == OrderStage.Confirmed || o.Stage == OrderStage.InProgress || o.Stage == OrderStage.Completed))
                .OrderByDescending(o => o.OrderDate).ThenByDescending(o => o.CreatedAt)
                .Select(o => new { PartyId = o.CustomerId, Date = o.OrderDate, Kg = o.Lines.Sum(l => l.QuantityKg) })
                .ToListAsync(ct))
            .ToLookup(o => o.PartyId, o => (o.Date, o.Kg));
        var supplies = (await db.Supplies.AsNoTracking()
                .Where(s => ids.Contains(s.SupplierId) && s.DeletedAt == null && s.Status == SupplyStatus.Received)
                .OrderByDescending(s => s.SupplyDate).ThenByDescending(s => s.CreatedAt)
                .Select(s => new { PartyId = s.SupplierId, Date = s.SupplyDate, Kg = s.Lines.Sum(l => l.QuantityKg) })
                .ToListAsync(ct))
            .ToLookup(s => s.PartyId, s => (s.Date, s.Kg));

        PartySummary Summary(IEnumerable<(DateOnly Date, decimal Kg)> deals, bool dueFollowUp,
            DateTimeOffset? lastContact, DateTimeOffset? nextFollowUp)
        {
            var list = deals.ToList();
            return new PartySummary(
                PartyStatusCalculator.Calculate(list.Select(d => d.Date).ToList(), dueFollowUp, today, rules),
                list.Count == 0 ? null : list[0].Date, list.Count == 0 ? null : list[0].Kg,
                lastContact, nextFollowUp);
        }

        var result = new Dictionary<Guid, (PartySummary?, PartySummary?)>();
        foreach (var p in parties)
        {
            var mine = interactions[p.Id].ToList();
            var lastContact = mine.Count == 0 ? (DateTimeOffset?)null : mine.Max(i => i.OccurredAt);
            var open = mine.Where(i => i.NextFollowUpAt is not null && !i.FollowUpDone)
                .Select(i => i.NextFollowUpAt!.Value).ToList();
            var due = open.Any(f => f <= now);
            DateTimeOffset? next = open.Count == 0 ? null : open.Min();
            result[p.Id] = (
                p.IsCustomer ? Summary(orders[p.Id], due, lastContact, next) : null,
                p.IsSupplier ? Summary(supplies[p.Id], due, lastContact, next) : null);
        }
        return result;
    }

    private async Task<StatusRules> LoadStatusRulesAsync(CancellationToken ct)
    {
        var settings = await db.AppSettings.AsNoTracking()
            .Where(s => s.Key.StartsWith("status."))
            .ToDictionaryAsync(s => s.Key, s => s.Value, ct);
        var defaults = new StatusRules();
        int Int(string key, int fallback) =>
            settings.TryGetValue(key, out var v) && int.TryParse(v, CultureInfo.InvariantCulture, out var i) && i > 0 ? i : fallback;
        decimal Dec(string key, decimal fallback) =>
            settings.TryGetValue(key, out var v) && decimal.TryParse(v, CultureInfo.InvariantCulture, out var d) && d > 0 ? d : fallback;
        return new StatusRules(
            Int(StatusRules.ActiveDaysKey, defaults.ActiveDays),
            Int(StatusRules.StoppedDaysKey, defaults.StoppedDays),
            Dec(StatusRules.OverdueFactorKey, defaults.OverdueFactor));
    }
}
