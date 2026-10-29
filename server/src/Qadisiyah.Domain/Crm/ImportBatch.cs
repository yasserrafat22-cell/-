namespace Qadisiyah.Domain.Crm;

/// <summary>
/// عملية استيراد Excel واحدة بمعرف ثابت يولده التطبيق: إعادة إرسال نفس العملية لا تكرر البيانات،
/// ويُحفظ ملخص النتيجة ومن رفع الملف ومتى.
/// </summary>
public class ImportBatch
{
    public Guid Id { get; set; }
    public required string Kind { get; set; }
    public required string FileSha256 { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>ملخص JSON: المضاف والموجود والمرفوض وما يحتاج مراجعة.</summary>
    public required string Summary { get; set; }
}
