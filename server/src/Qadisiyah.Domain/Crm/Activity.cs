using Qadisiyah.Domain.Common;

namespace Qadisiyah.Domain.Crm;

public enum ContactChannel
{
    Call,
    WhatsApp,
    Visit,
    Other,
}

/// <summary>
/// تواصل مسجل بنتيجته. «آخر تواصل» يُحسب من هذه السجلات فقط؛ مجرد فتح تطبيق
/// الاتصال لا يُعد تواصلًا.
/// </summary>
public class Interaction : TrackedEntity
{
    public Guid PartyId { get; set; }
    public ContactChannel Channel { get; set; }
    public Guid OutcomeId { get; set; }
    public DateTimeOffset OccurredAt { get; set; }
    public string? Notes { get; set; }
    public DateTimeOffset? NextFollowUpAt { get; set; }
    public bool Remind { get; set; }

    /// <summary>تُغلق المتابعة تلقائيًا عند تسجيل تواصل لاحق مع نفس الطرف.</summary>
    public bool FollowUpDone { get; set; }
}

/// <summary>مراحل الطلب (قرار T4). «معلق» علامة منفصلة وليست مرحلة.</summary>
public enum OrderStage
{
    Inquiry,
    Quotation,
    Confirmed,
    InProgress,
    Completed,
    Cancelled,
}

public static class OrderStages
{
    private static readonly Dictionary<OrderStage, OrderStage[]> Allowed = new()
    {
        [OrderStage.Inquiry] = [OrderStage.Quotation, OrderStage.Confirmed, OrderStage.Cancelled],
        [OrderStage.Quotation] = [OrderStage.Inquiry, OrderStage.Confirmed, OrderStage.Cancelled],
        [OrderStage.Confirmed] = [OrderStage.InProgress, OrderStage.Completed, OrderStage.Cancelled],
        [OrderStage.InProgress] = [OrderStage.Completed, OrderStage.Cancelled],
        [OrderStage.Completed] = [],
        [OrderStage.Cancelled] = [],
    };

    public static bool CanTransition(OrderStage from, OrderStage to) => Allowed[from].Contains(to);

    public static bool IsTerminal(OrderStage stage) => Allowed[stage].Length == 0;

    /// <summary>الطلب يُحتسب «شراءً» في آخر طلب والتقارير (لا الاستفسار ولا عرض السعر).</summary>
    public static bool IsPurchase(OrderStage stage) =>
        stage is OrderStage.Confirmed or OrderStage.InProgress or OrderStage.Completed;
}

public class Order : TrackedEntity
{
    public Guid CustomerId { get; set; }
    public DateOnly OrderDate { get; set; }
    public OrderStage Stage { get; set; }
    public bool OnHold { get; set; }
    public Guid? RepresentativeId { get; set; }
    public string? Notes { get; set; }

    /// <summary>موقع التسليم لهذا الطلب فقط (لا يغيّر الموقع الافتراضي للعميل).</summary>
    public Guid? DeliveryLocationId { get; set; }

    public List<OrderLine> Lines { get; } = [];
}

public class OrderLine
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid OrderId { get; set; }

    /// <summary>ترتيب الخامة داخل الطلب كما أدخلها المستخدم.</summary>
    public int LineNo { get; set; }

    public Guid MaterialId { get; set; }
    public Guid? GradeId { get; set; }

    /// <summary>العميل يقبل أي شركة وأي Grade (يختلف عن «غير محدد»).</summary>
    public bool OpenSpec { get; set; }

    public Guid? OriginCountryId { get; set; }
    public decimal Quantity { get; set; }
    public Guid UnitId { get; set; }

    /// <summary>الكمية محولة إلى كجم وقت التسجيل لتجميع الكميات في التقارير.</summary>
    public decimal QuantityKg { get; set; }
}

public class OrderStageChange
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid OrderId { get; set; }
    public OrderStage? FromStage { get; set; }
    public OrderStage ToStage { get; set; }
    public DateTimeOffset At { get; set; }
    public Guid By { get; set; }
}

/// <summary>
/// حالة التوريد. التوريد «متوقع» لا يُحتسب توريدًا فعليًا حتى يصبح «مستلمًا»؛
/// عرض السعر أو الكمية المقترحة ليس توريدًا.
/// </summary>
public enum SupplyStatus
{
    Expected,
    Received,
    Cancelled,
}

public class Supply : TrackedEntity
{
    public Guid SupplierId { get; set; }
    public DateOnly SupplyDate { get; set; }
    public SupplyStatus Status { get; set; }
    public string? Notes { get; set; }

    /// <summary>موقع التحميل لهذا التوريد فقط (لا يغيّر الموقع الافتراضي للمورد).</summary>
    public Guid? LoadingLocationId { get; set; }
    public List<SupplyLine> Lines { get; } = [];
}

public class SupplyLine
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid SupplyId { get; set; }
    public int LineNo { get; set; }

    public Guid MaterialId { get; set; }
    public Guid? GradeId { get; set; }
    public Guid? OriginCountryId { get; set; }
    public decimal Quantity { get; set; }
    public Guid UnitId { get; set; }
    public decimal QuantityKg { get; set; }
}
