namespace Qadisiyah.Domain.Reference;

/// <summary>
/// عنصر في قائمة أساسية يديرها المدير (أنواع النشاط، نتائج التواصل،
/// المحافظات، العملات). <see cref="Semantic"/> نوع دلالي ثابت تعتمد عليه
/// الحسابات (مثل «تم التواصل بنجاح»)، بينما الاسم المعروض قابل للتعديل.
/// </summary>
public class LookupItem
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public required string Category { get; set; }
    public required string Code { get; set; }
    public required string NameAr { get; set; }
    public string? NameEn { get; set; }
    public string? Semantic { get; set; }

    /// <summary>للأنواع ونتائج التواصل: customer أو supplier أو both.</summary>
    public string AppliesTo { get; set; } = LookupAppliesTo.Both;

    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsSystem { get; set; }
}

public static class LookupCategories
{
    public const string ActivityType = "activity_type";
    public const string ContactOutcome = "contact_outcome";
    public const string Governorate = "governorate";
    public const string Currency = "currency";

    /// <summary>بلد الصنع (مستقل عن جنسية الشركة المصنّعة).</summary>
    public const string Country = "country";
}

public static class LookupAppliesTo
{
    public const string Customer = "customer";
    public const string Supplier = "supplier";
    public const string Both = "both";
}

/// <summary>الأنواع الدلالية الثابتة لنتائج التواصل (قرار T3).</summary>
public static class ContactOutcomeSemantics
{
    public const string Reached = "reached";
    public const string NoAnswer = "no_answer";
    public const string Pending = "pending";
    public const string PriceRequested = "price_requested";
    public const string FollowUpAgreed = "follow_up_agreed";
    public const string Other = "other";
}

/// <summary>
/// وحدة وزن بمعامل تحويل صريح إلى الكيلوجرام (الوحدة القياسية — قرار السؤال 5).
/// </summary>
public class Unit
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public required string Code { get; set; }
    public required string NameAr { get; set; }
    public decimal FactorToKg { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;

    public decimal ToKg(decimal quantity) => quantity * FactorToKg;
}

public class Material
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public required string Code { get; set; }
    public required string NameAr { get; set; }
    public string? NameEn { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public List<MaterialAlias> Aliases { get; } = [];
    public List<Grade> Grades { get; } = [];
}

/// <summary>اسم بديل أو اختصار للخامة يُستخدم في البحث (المرحلة 4).</summary>
public class MaterialAlias
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid MaterialId { get; set; }
    public required string Alias { get; set; }
    public required string Normalized { get; set; }
}

/// <summary>
/// الشركة المصنّعة للخامة (مثل SABIC). منفصلة عن المورد التجاري الذي يبيعها.
/// </summary>
public class Manufacturer
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public required string Name { get; set; }

    /// <summary>الاسم بعد التطبيع لمنع تكرار «Sabic» و«SABIC».</summary>
    public required string NormalizedName { get; set; }

    public bool IsActive { get; set; } = true;
}

/// <summary>
/// Grade محدد لخامة من شركة مصنّعة. الـ Grades المسجلة قبل إضافة الشركات
/// تبقى بلا شركة («الشركة غير محددة») ولا تُربط بشركة إلا يدويًا من المدير.
/// </summary>
public class Grade
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public Guid MaterialId { get; set; }
    public Guid? ManufacturerId { get; set; }
    public required string Code { get; set; }

    /// <summary>الكود دون فواصل أو حالة حروف لمنع تكرار «SG-5» و«sg5».</summary>
    public required string NormalizedCode { get; set; }

    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;

    /// <summary>ما يضيفه المندوب أثناء التسجيل يبقى «بانتظار التحقق» حتى يعتمده المدير.</summary>
    public bool IsVerified { get; set; } = true;

    public Guid? CreatedBy { get; set; }
    public DateTimeOffset? CreatedAt { get; set; }
    public List<GradeOrigin> Origins { get; } = [];
}

/// <summary>بلد صنع معروف للـ Grade؛ قد يكون للـ Grade أكثر من بلد.</summary>
public class GradeOrigin
{
    public Guid GradeId { get; set; }
    public Guid CountryId { get; set; }
}

public class Representative
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public required string Name { get; set; }
    public string? Phone { get; set; }

    /// <summary>حساب المستخدم المرتبط إن وُجد؛ يحدد «عملائي» في صلاحية التعديل.</summary>
    public Guid? UserId { get; set; }

    public bool IsActive { get; set; } = true;
}

/// <summary>إعداد قابل للضبط من الإدارة (مثل حدود تصنيف العملاء).</summary>
public class AppSetting
{
    public required string Key { get; set; }
    public required string Value { get; set; }
}
