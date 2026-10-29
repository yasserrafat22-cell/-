using Qadisiyah.Domain.Common;

namespace Qadisiyah.Domain.Crm;

/// <summary>موظف أو جهة اتصال داخل الشركة (الاسم، الوظيفة، رقم موبايل واحد).</summary>
public class PartyContact : TrackedEntity
{
    public Guid PartyId { get; set; }
    public required string Name { get; set; }
    public string? JobTitle { get; set; }

    /// <summary>رقم بصيغة E.164 بعد التحقق.</summary>
    public string? Mobile { get; set; }

    /// <summary>جهة الاتصال الأساسية (واحدة على الأكثر لكل طرف).</summary>
    public bool IsPrimary { get; set; }
}
