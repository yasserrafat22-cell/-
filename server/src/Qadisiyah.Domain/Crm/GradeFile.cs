namespace Qadisiyah.Domain.Crm;

public enum GradeFileKind
{
    Photo,
    DataSheet,
}

/// <summary>
/// صورة الـ Grade وملف المواصفات (Datasheet PDF) في الكتالوج الموحد، مرتبطة بالـ Grade
/// نفسه لا بمورد معين. ملف واحد حالي لكل نوع؛ الاستبدال يحذف السابق منطقيًا.
/// </summary>
public class GradeFile
{
    public Guid Id { get; set; }
    public Guid GradeId { get; set; }
    public GradeFileKind Kind { get; set; }
    public required string FileName { get; set; }
    public required string ContentType { get; set; }
    public long SizeBytes { get; set; }
    public required string Sha256 { get; set; }
    public required string StorageKey { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }
    public Guid? DeletedBy { get; set; }
}
