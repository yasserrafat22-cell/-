namespace Qadisiyah.Domain.Crm;

/// <summary>حالات صف الإدخال السريع (لصق مباشر أو Excel).</summary>
public static class ImportEntryStatus
{
    /// <summary>ناقص أو غير صالح: بانتظار الاستكمال (ليس عميلًا أو موردًا بعد).</summary>
    public const string Pending = "pending";

    /// <summary>مرشح مكرر (نفس الرقم أو اسم مشابه): بانتظار قرار المستخدم.</summary>
    public const string Duplicate = "duplicate";

    /// <summary>أصبح بطاقة عميل أو مورد (أُنشئت، أو أُضيفت خاماته لسجل موجود بتأكيد).</summary>
    public const string Completed = "completed";

    /// <summary>لا يملك المستخدم صلاحية إضافته (لا يفيده الاستكمال).</summary>
    public const string Failed = "failed";

    /// <summary>استُبعد بقرار المستخدم أو بالتراجع عن الدفعة؛ يبقى في سجل الدفعة.</summary>
    public const string Discarded = "discarded";
}

/// <summary>
/// صف واحد من دفعة إدخال سريع. منفصل تمامًا عن سجلات العملاء والموردين: الصف الناقص لا يُحسب
/// عميلًا أو موردًا ولا يظهر في البحث أو المطابقة حتى يكتمل (الاسم، موبايل مصري صحيح، الخامة، الـ Grade)
/// فيُنشأ له سجل عادي مرة واحدة بنفس المعرف (إعادة المحاولة لا تكرر).
/// </summary>
public class ImportEntry
{
    public Guid Id { get; set; }
    public Guid BatchId { get; set; }
    public int RowNumber { get; set; }

    /// <summary>customer أو supplier، أو null عند عدم تحديده في الاستيراد المختلط.</summary>
    public string? Kind { get; set; }

    public string? Name { get; set; }
    public string? Phone { get; set; }
    public string? MaterialText { get; set; }
    public string? GradeText { get; set; }
    public string? ManufacturerText { get; set; }
    public Guid? MaterialId { get; set; }
    public Guid? GradeId { get; set; }

    public required string Status { get; set; }

    /// <summary>سجل العميل/المورد الناتج (أُنشئ أو أُضيف إليه).</summary>
    public Guid? PartyId { get; set; }

    /// <summary>true إذا أنشأ هذا الصف السجل (يمكن التراجع عنه بأمان)، false إذا أُضيف لسجل موجود.</summary>
    public bool CreatedParty { get; set; }

    /// <summary>السجل الموجود المرشح كمكرر (إن كان ظاهرًا للمستخدم).</summary>
    public Guid? DuplicateOfId { get; set; }

    /// <summary>سبب آخر رفض من السيرفر (مكرر، صلاحية...) للعرض.</summary>
    public string? Note { get; set; }

    public Guid CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public Guid UpdatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public void Touch(Guid userId, DateTimeOffset now)
    {
        UpdatedAt = now;
        UpdatedBy = userId;
    }
}
