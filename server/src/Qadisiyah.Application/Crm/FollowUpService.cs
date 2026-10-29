using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;

namespace Qadisiyah.Application.Crm;

public sealed record FollowUpItem(
    Guid InteractionId,
    Guid PartyId,
    string PartyName,
    bool IsCustomer,
    DateTimeOffset DueAt,
    string Status,
    bool Remind,
    bool Mine,
    string? RepresentativeName,
    string? Notes);

/// <summary>
/// المتابعات المفتوحة (المتأخرة ومتابعات اليوم والقادمة) للسجلات الظاهرة للمستخدم فقط.
/// <c>Mine</c> = المستخدم هو المندوب المسؤول أو من سجّل المتابعة: لهذه فقط تُرسل
/// إشعارات الهاتف، والمدير والسكرتارية يرون الباقي في القائمة دون إشعار.
/// </summary>
public sealed class FollowUpService(IAppDbContext db, ICurrentUser user, PartyAccess access, TimeProvider clock)
{
    public async Task<IReadOnlyList<FollowUpItem>> ListAsync(int days, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var until = now.AddDays(Math.Clamp(days, 0, 60));
        var visible = access.Visible(db.Parties.AsNoTracking().Where(p => p.DeletedAt == null));
        if (!access.CanSeeSuppliers)
            visible = visible.Where(p => p.IsCustomer);
        var today = BusinessClock.Today(clock);

        var rows = await (
            from i in db.Interactions.AsNoTracking()
            join p in visible on i.PartyId equals p.Id
            where i.NextFollowUpAt != null && !i.FollowUpDone && i.DeletedAt == null && i.NextFollowUpAt <= until
            orderby i.NextFollowUpAt
            select new
            {
                i.Id, i.PartyId, p.Name, p.IsCustomer, Due = i.NextFollowUpAt!.Value, i.Remind, i.Notes, i.CreatedBy,
                Rep = db.Representatives.Where(r => r.Id == p.RepresentativeId).Select(r => new { r.Name, r.UserId })
                    .FirstOrDefault(),
            })
            .Take(500)
            .ToListAsync(ct);

        return rows.Select(r =>
        {
            var day = BusinessClock.Day(r.Due);
            var status = day < today ? "overdue" : day == today ? "today" : "upcoming";
            return new FollowUpItem(r.Id, r.PartyId, r.Name, r.IsCustomer, r.Due, status, r.Remind,
                r.Rep?.UserId == user.UserId || r.CreatedBy == user.UserId, r.Rep?.Name, r.Notes);
        }).ToList();
    }
}
