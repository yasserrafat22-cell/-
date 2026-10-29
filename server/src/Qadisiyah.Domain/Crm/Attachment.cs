namespace Qadisiyah.Domain.Crm;

public enum AttachmentKind
{
    Logo,
    ProductPhoto,
    TechnicalDataSheet,
    Other,
}

/// <summary>
/// ملف مرفق بعميل أو مورد. المحتوى في التخزين الدائم للمرفقات (خارج حاوية
/// التطبيق)، ولا يُعرض إلا عبر السيرفر لمن يملك صلاحية الاطلاع على السجل.
/// ملف TDS مرتبط بـ Grade محدد (ومنه الشركة المصنّعة والخامة) حتى لا تختلط
/// ملفات الشركات. الحذف منطقي فقط.
/// </summary>
public class Attachment
{
    public Guid Id { get; set; }
    public Guid PartyId { get; set; }
    public AttachmentKind Kind { get; set; }
    public Guid? MaterialId { get; set; }
    public Guid? GradeId { get; set; }
    public required string FileName { get; set; }
    public required string ContentType { get; set; }
    public long SizeBytes { get; set; }
    public required string Sha256 { get; set; }
    public required string StorageKey { get; set; }
    public string? Caption { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }
    public Guid? DeletedBy { get; set; }
}
