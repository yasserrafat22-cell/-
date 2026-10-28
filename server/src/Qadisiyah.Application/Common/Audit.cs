using System.Text.Json;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Common;

public static class AuditExtensions
{
    /// <summary>يضيف سجل تدقيق ضمن نفس المعاملة (يُحفظ مع التغيير نفسه).</summary>
    public static void Audit(this IAppDbContext db, ICurrentUser user, TimeProvider clock,
        string action, string entityType, Guid entityId, object? data = null) =>
        db.AuditEntries.Add(new AuditEntry
        {
            At = clock.GetUtcNow(),
            UserId = user.UserId,
            DeviceId = user.DeviceId,
            Action = action,
            EntityType = entityType,
            EntityId = entityId,
            Data = data is null ? null : JsonSerializer.Serialize(data),
        });
}
