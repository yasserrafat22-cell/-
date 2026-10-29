using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Crm;

public sealed record AuditItem(
    DateTimeOffset At,
    string Action,
    string? EntityType,
    Guid? EntityId,
    string? UserName,
    string? Data);

/// <summary>سجل التدقيق الكامل (من فعل ماذا ومتى) لمن يملك صلاحية الاطلاع عليه.</summary>
public sealed class AuditService(IAppDbContext db, ICurrentUser user)
{
    public async Task<Result<PagedResult<AuditItem>>> ListAsync(
        string? action, Guid? entityId, Guid? userId, int skip, int take, CancellationToken ct)
    {
        if (!user.Has(Permissions.AuditView))
            return AppError.Forbidden();
        var query = db.AuditEntries.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(action))
            query = query.Where(a => a.Action.StartsWith(action.Trim()));
        if (entityId is { } id)
            query = query.Where(a => a.EntityId == id);
        if (userId is { } uid)
            query = query.Where(a => a.UserId == uid);

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(a => a.At).ThenByDescending(a => a.Id)
            .Skip(Math.Max(0, skip)).Take(Math.Clamp(take, 1, 200))
            .Select(a => new AuditItem(a.At, a.Action, a.EntityType, a.EntityId,
                db.Users.Where(u => u.Id == a.UserId).Select(u => u.DisplayName).FirstOrDefault(), a.Data))
            .ToListAsync(ct);
        return new PagedResult<AuditItem>(items, total);
    }
}
