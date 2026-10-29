using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

/// <summary>
/// تصدير العملاء أو الموردين إلى Excel بنفس صلاحيات العرض: المندوب يصدّر عملاءه فقط،
/// والموردون لمن يطّلع عليهم فقط.
/// </summary>
public sealed class ExportService(IAppDbContext db, PartyAccess access, RegistryService registry, TimeProvider clock)
{
    private const int MaxRows = 10_000;

    public async Task<Result<(byte[] Content, string FileName)>> PartiesAsync(string role, CancellationToken ct)
    {
        var supplier = role == "supplier";
        if (role is not ("customer" or "supplier"))
            return AppError.Validation("حدد العملاء أو الموردين");
        if (supplier && !access.CanSeeSuppliers)
            return AppError.Forbidden();

        var items = new List<RegistryItem>();
        while (items.Count < MaxRows)
        {
            var page = await registry.ListAsync(new RegistryQuery(Role: role, Skip: items.Count, Take: 50), ct);
            items.AddRange(page.Items);
            if (page.Items.Count == 0 || items.Count >= page.Total)
                break;
        }

        var names = await db.LookupItems.AsNoTracking().ToDictionaryAsync(l => l.Id, l => l.NameAr, ct);
        string? Name(Guid? id) => id is { } v && names.TryGetValue(v, out var n) ? n : null;
        string Status(PartyStatus? s) => s switch
        {
            PartyStatus.New => "جديد",
            PartyStatus.Active => "نشط",
            PartyStatus.NeedsFollowUp => "يحتاج متابعة",
            PartyStatus.Stopped => "متوقف",
            _ => "",
        };

        var headers = new[]
        {
            "الاسم", supplier ? "نوع المورد" : "نشاط العميل", "الهاتف", "المحافظة", "المنطقة", "المندوب المسؤول",
            "الحالة", supplier ? "آخر توريد" : "آخر طلب", "آخر تواصل", supplier ? "الخامات المتاحة" : "الخامات المطلوبة",
            "تاريخ الإنشاء",
        };
        var rows = items.Select(i => (IReadOnlyList<object?>)
        [
            i.Name, Name(i.ActivityId), i.PrimaryPhone, Name(i.GovernorateId), i.Region, i.RepresentativeName,
            Status(i.Summary?.Status), i.Summary?.LastDealDate,
            i.Summary?.LastContactAt is { } at ? DateOnly.FromDateTime(at.UtcDateTime) : null,
            string.Join("، ", i.Specs.Select(PartyService.SpecLabel)),
            DateOnly.FromDateTime(i.CreatedAt.UtcDateTime),
        ]);
        var content = XlsxWriter.Write(supplier ? "الموردون" : "العملاء", headers, rows);
        return (content, $"{(supplier ? "suppliers" : "customers")}-{clock.GetUtcNow():yyyyMMdd}.xlsx");
    }
}
