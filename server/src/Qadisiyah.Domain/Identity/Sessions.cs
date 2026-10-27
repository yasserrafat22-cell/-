namespace Qadisiyah.Domain.Identity;

/// <summary>
/// جهاز مسجل. المعرف يولده التطبيق مرة واحدة لكل تثبيت.
/// إلغاء الجهاز يمنع الدخول منه ويُبطل كل جلساته.
/// </summary>
public class Device
{
    public Guid Id { get; set; }
    public required string Name { get; set; }
    public Guid? LastUserId { get; set; }
    public DateTimeOffset FirstSeenAt { get; set; }
    public DateTimeOffset LastSeenAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public Guid? RevokedBy { get; set; }
    public string? RevokeReason { get; set; }

    public bool IsRevoked => RevokedAt is not null;
}

/// <summary>
/// رمز تحديث يُستخدم مرة واحدة (rotation). كل الرموز الناتجة عن دخول واحد
/// تشترك في <see cref="FamilyId"/>؛ إعادة استخدام رمز مستهلك تُلغي العائلة كلها.
/// </summary>
public class RefreshToken
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid UserId { get; set; }
    public Guid DeviceId { get; set; }
    public Guid FamilyId { get; set; }

    /// <summary>SHA-256 للرمز؛ الرمز نفسه لا يُخزن.</summary>
    public required string TokenHash { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? ConsumedAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
}

/// <summary>سجل تدقيق للأحداث المهمة: من فعل ماذا ومتى ومن أي جهاز.</summary>
public class AuditEntry
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public DateTimeOffset At { get; set; }
    public Guid? UserId { get; set; }
    public Guid? DeviceId { get; set; }
    public required string Action { get; set; }
    public string? EntityType { get; set; }
    public Guid? EntityId { get; set; }

    /// <summary>تفاصيل بصيغة JSON.</summary>
    public string? Data { get; set; }

    public string? IpAddress { get; set; }
}
