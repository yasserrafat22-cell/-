using Qadisiyah.Domain.Common;

namespace Qadisiyah.Domain.Crm;

/// <summary>
/// شركة أو شخص يتعامل معه: عميل أو مورد أو كلاهما بهوية واحدة دون تكرار
/// (قرار السؤال 2).
/// </summary>
public class Party : TrackedEntity
{
    public required string Name { get; set; }
    public required string NormalizedName { get; set; }

    /// <summary>رقم تسلسلي للعرض (C000125)؛ تولده قاعدة البيانات ولا يُعدّل.</summary>
    public long Number { get; set; }

    /// <summary>تاريخ السجل كما اختاره المدير/السكرتارية (افتراضيًا يوم الإنشاء). مستقل عن CreatedAt الفعلي.</summary>
    public DateOnly? RecordDate { get; set; }
    public bool IsCustomer { get; set; }
    public bool IsSupplier { get; set; }

    /// <summary>سُجل من استيراد Excel بدون اسم؛ يُستكمل لاحقًا (لا يُعد تعديلًا لبيانات محفوظة).</summary>
    public bool NameMissing { get; set; }

    /// <summary>Grade من الاستيراد لسجل غير مصنف بعد؛ يتحول لخامة عميل أو منتج مورد عند تحديد النوع.</summary>
    public Guid? PendingGradeId { get; set; }

    /// <summary>نوع النشاط كعميل (مصنع/محول/تاجر/موزع/أخرى).</summary>
    public Guid? CustomerActivityId { get; set; }

    /// <summary>نوع المورد (مصنع/مستورد/تاجر/موزع/أخرى).</summary>
    public Guid? SupplierActivityId { get; set; }

    public Guid? RepresentativeId { get; set; }
    public string? Email { get; set; }
    public string? Notes { get; set; }

    // الموقع اختياري ويُستكمل لاحقًا (قرار T1).
    public string CountryCode { get; set; } = "EG";
    public Guid? GovernorateId { get; set; }
    public string? Region { get; set; }
    public string? AddressLine { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }

    public List<PartyPhone> Phones { get; } = [];
    public List<CustomerInterest> Interests { get; } = [];
    public List<SupplierProduct> Products { get; } = [];
}

public class PartyPhone
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid PartyId { get; set; }

    /// <summary>الرقم موحدًا بصيغة E.164.</summary>
    public required string E164 { get; set; }

    public string? Label { get; set; }
    public bool IsPrimary { get; set; }

    /// <summary>رقم واتساب عند اختلافه عن رقم الاتصال.</summary>
    public string? WhatsAppE164 { get; set; }
}

/// <summary>خامة يحتاجها العميل، مع Grade وكمية شهرية متوقعة عند توفرها.</summary>
public class CustomerInterest
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid PartyId { get; set; }
    public Guid MaterialId { get; set; }
    public Guid? GradeId { get; set; }
    public decimal? MonthlyQuantity { get; set; }
    public Guid? UnitId { get; set; }

    /// <summary>العميل يقبل أي شركة وأي Grade لهذه الخامة (مواصفات مفتوحة).</summary>
    public bool OpenSpec { get; set; }

    public Guid? OriginCountryId { get; set; }
}

/// <summary>منتج متاح لدى المورد: خامة وGrade، وتُربط به عروض الأسعار.</summary>
public class SupplierProduct
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid PartyId { get; set; }
    public Guid MaterialId { get; set; }
    public Guid? GradeId { get; set; }
    public Guid? OriginCountryId { get; set; }
    public string? Notes { get; set; }
    public bool IsActive { get; set; } = true;
}

/// <summary>
/// عرض سعر من مورد. لا يُعدّل ولا يُحذف؛ كل عرض جديد سجل جديد ليبقى تاريخ
/// الأسعار كاملًا. وجود سعر لا يعني توفر المنتج أو صلاحية العرض.
/// </summary>
public class PriceQuote
{
    public Guid Id { get; set; }
    public Guid SupplierProductId { get; set; }
    public decimal Price { get; set; }
    public required string Currency { get; set; }
    public Guid UnitId { get; set; }
    public DateOnly QuoteDate { get; set; }
    public DateOnly? ValidUntil { get; set; }
    public string? TransportNote { get; set; }
    public string? TaxNote { get; set; }
    public string? Notes { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public Guid CreatedBy { get; set; }
}

/// <summary>مفضلة المستخدم: لكل مستخدم قائمته الخاصة من أهم العملاء والموردين.</summary>
public class UserFavorite
{
    public Guid UserId { get; set; }
    public Guid PartyId { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
