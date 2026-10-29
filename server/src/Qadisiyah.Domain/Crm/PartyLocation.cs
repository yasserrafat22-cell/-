using Qadisiyah.Domain.Common;

namespace Qadisiyah.Domain.Crm;

public enum LocationKind
{
    HeadOffice,
    Factory,
    Warehouse,
    Loading,
    Delivery,
    Other,
}

/// <summary>
/// موقع من مواقع العميل أو المورد. رابط الخريطة يُحفظ كما هو دائمًا، والإحداثيات
/// اختيارية (لا يمكن استخراجها من كل الروابط). موقع افتراضي واحد على الأكثر لكل طرف.
/// </summary>
public class PartyLocation : TrackedEntity
{
    public Guid PartyId { get; set; }
    public LocationKind Kind { get; set; }
    public string? Label { get; set; }
    public string? AddressLine { get; set; }
    public string? MapsUrl { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? AccessNotes { get; set; }
    public bool IsDefault { get; set; }
}
