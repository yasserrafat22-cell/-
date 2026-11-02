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

    // الإدخال السريع (إضافية؛ null لدفعات الاستيراد السابقة).

    /// <summary>paste أو excel.</summary>
    public string? Method { get; set; }

    /// <summary>customer أو supplier أو mixed.</summary>
    public string? Audience { get; set; }

    public string? FileName { get; set; }
    public int RowCount { get; set; }
    public int CreatedCount { get; set; }
    public int PendingCount { get; set; }
    public int DuplicateCount { get; set; }
    public int FailedCount { get; set; }

    /// <summary>processed أو undone أو partially_undone.</summary>
    public string? Status { get; set; }
}
