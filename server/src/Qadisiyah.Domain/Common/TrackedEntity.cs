namespace Qadisiyah.Domain.Common;

/// <summary>
/// كيان تجاري يُنشأ من التطبيق: المعرف يولده الجهاز (يسمح بالإنشاء دون اتصال
/// وبإعادة الإرسال الآمن)، ويحتفظ بمن أنشأ وعدّل ومتى. لا حذف فعلي، بل
/// <see cref="DeletedAt"/>.
/// </summary>
public abstract class TrackedEntity
{
    public Guid Id { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid UpdatedBy { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>رقم نسخة السجل (xmin في PostgreSQL) لكشف التعديلات المتزامنة.</summary>
    public uint Version { get; set; }

    public void Touch(Guid userId, DateTimeOffset now)
    {
        UpdatedAt = now;
        UpdatedBy = userId;
    }

    public void Stamp(Guid userId, DateTimeOffset now)
    {
        CreatedAt = now;
        CreatedBy = userId;
        Touch(userId, now);
    }
}
