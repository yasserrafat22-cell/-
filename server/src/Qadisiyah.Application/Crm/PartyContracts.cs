using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

public sealed record PhoneInput(string Number, string? Label = null, string? WhatsApp = null);

/// <summary>خامة يهتم بها العميل. <c>GradeCode</c> للتوافق مع نسخ التطبيق السابقة.</summary>
public sealed record InterestInput(Guid MaterialId, string? GradeCode = null, decimal? MonthlyQuantity = null,
    Guid? UnitId = null, Guid? GradeId = null, Guid? OriginCountryId = null, bool OpenSpec = false)
{
    public SpecInput Spec => new(MaterialId, GradeId, OriginCountryId, OpenSpec, GradeCode);
}

/// <summary>خامة يوفرها المورد بمواصفات محددة (لا مواصفات مفتوحة للمورد).</summary>
public sealed record ProductInput(Guid MaterialId, string? GradeCode = null, string? Notes = null,
    Guid? GradeId = null, Guid? OriginCountryId = null)
{
    public SpecInput Spec => new(MaterialId, GradeId, OriginCountryId, false, GradeCode);
}

/// <summary>
/// تسجيل عميل أو مورد. المعرف يولده التطبيق؛ إعادة الإرسال بنفس المعرف لا
/// تنشئ نسخة ثانية.
/// </summary>
public sealed record CreatePartyRequest(
    Guid Id,
    string Name,
    bool IsCustomer,
    bool IsSupplier,
    IReadOnlyList<PhoneInput> Phones,
    Guid? CustomerActivityId = null,
    Guid? SupplierActivityId = null,
    Guid? RepresentativeId = null,
    string? Email = null,
    string? Notes = null,
    Guid? GovernorateId = null,
    string? Region = null,
    string? AddressLine = null,
    double? Latitude = null,
    double? Longitude = null,
    IReadOnlyList<InterestInput>? Interests = null,
    IReadOnlyList<ProductInput>? Products = null);

/// <summary>
/// تعديل البيانات واستكمالها. <see cref="Version"/> هو رقم النسخة المقروء؛
/// إذا عدّل غيرك السجل بعدها يُرفض التعديل بدل استبدال تعديله بصمت.
/// </summary>
public sealed record UpdatePartyRequest(
    uint Version,
    string Name,
    IReadOnlyList<PhoneInput> Phones,
    Guid? CustomerActivityId = null,
    Guid? SupplierActivityId = null,
    Guid? RepresentativeId = null,
    string? Email = null,
    string? Notes = null,
    Guid? GovernorateId = null,
    string? Region = null,
    string? AddressLine = null,
    double? Latitude = null,
    double? Longitude = null,
    IReadOnlyList<InterestInput>? Interests = null);

/// <summary>إضافة دور ثانٍ لنفس الشركة (عميل يصبح موردًا أيضًا أو العكس).</summary>
public sealed record AddRoleRequest(bool IsCustomer, bool IsSupplier, Guid? CustomerActivityId = null, Guid? SupplierActivityId = null);

public sealed record PhoneDto(Guid Id, string E164, string? Label, bool IsPrimary, string? WhatsAppE164);

public sealed record InterestDto(Guid Id, Guid MaterialId, string MaterialCode, Guid? GradeId, string? GradeCode,
    decimal? MonthlyQuantity, Guid? UnitId, SpecInfo? Spec = null);

public sealed record LatestPriceDto(Guid QuoteId, decimal Price, string Currency, string UnitCode, DateOnly QuoteDate,
    DateOnly? ValidUntil, bool Expired);

public sealed record ProductDto(Guid Id, Guid MaterialId, string MaterialCode, Guid? GradeId, string? GradeCode,
    string? Notes, LatestPriceDto? LatestPrice, SpecInfo? Spec = null);

/// <summary>
/// ملخص مشتق من الأحداث المسجلة فقط: آخر طلب/توريد فعلي، آخر تواصل، والمتابعة
/// القادمة، والحالة المحسوبة بقواعد الإعدادات.
/// </summary>
public sealed record PartySummary(
    PartyStatus Status,
    DateOnly? LastDealDate,
    decimal? LastDealQuantityKg,
    DateTimeOffset? LastContactAt,
    DateTimeOffset? NextFollowUpAt);

public sealed record PartyDetail(
    Guid Id,
    uint Version,
    string Name,
    bool IsCustomer,
    bool IsSupplier,
    IReadOnlyList<PhoneDto> Phones,
    Guid? CustomerActivityId,
    Guid? SupplierActivityId,
    Guid? RepresentativeId,
    string? RepresentativeName,
    string? Email,
    string? Notes,
    string CountryCode,
    Guid? GovernorateId,
    string? Region,
    string? AddressLine,
    double? Latitude,
    double? Longitude,
    IReadOnlyList<InterestDto> Interests,
    IReadOnlyList<ProductDto> Products,
    PartySummary? CustomerSummary,
    PartySummary? SupplierSummary,
    bool CanEdit,
    DateTimeOffset CreatedAt,
    DateTimeOffset? UpdatedAt = null,
    bool IsFavorite = false,
    Guid? LogoAttachmentId = null);

public sealed record PartyListItem(Guid Id, string Name, bool IsCustomer, bool IsSupplier, string? PrimaryPhone,
    string? RepresentativeName);

public sealed record PagedResult<T>(IReadOnlyList<T> Items, int Total);

/// <summary>بيانات الطرف الموجود عند رفض التسجيل بسبب تكرار رقم الهاتف.</summary>
public sealed record DuplicatePartyInfo(Guid PartyId, string Name, bool IsCustomer, bool IsSupplier, string Phone);

public sealed record CreateQuoteRequest(
    Guid Id,
    decimal Price,
    string Currency,
    Guid UnitId,
    DateOnly QuoteDate,
    DateOnly? ValidUntil = null,
    string? TransportNote = null,
    string? TaxNote = null,
    string? Notes = null);

public sealed record QuoteDto(Guid Id, decimal Price, string Currency, Guid UnitId, string UnitCode, DateOnly QuoteDate,
    DateOnly? ValidUntil, bool Expired, string? TransportNote, string? TaxNote, string? Notes, DateTimeOffset CreatedAt);
