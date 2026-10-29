using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

/// <summary>
/// تصدير العملاء أو الموردين إلى Excel بنفس صلاحيات العرض: المندوب يصدّر عملاءه فقط،
/// والموردون لمن يطّلع عليهم فقط.
/// </summary>
public sealed record SearchExportRequest(string? Q, Guid? MaterialId = null, Guid? ManufacturerId = null,
    Guid? GradeId = null, IReadOnlyList<Guid>? PartyIds = null);

/// <summary>طلب مشاركة/طباعة من التطبيق: يُفحص على السيرفر ويُسجَّل قبل التنفيذ.</summary>
public sealed record ShareRequest(string Scope, int Count, string? Query = null);

public sealed class ExportService(IAppDbContext db, ICurrentUser user, PartyAccess access, RegistryService registry,
    SearchService search, TimeProvider clock)
{
    /// <summary>
    /// المشاركة الجماعية والطباعة والتصدير لمن يملك «استخراج التقارير» (المدير، السكرتارية،
    /// مديرو الأقسام). المندوب: بطاقة واحدة فقط في كل مرة.
    /// </summary>
    public bool CanShareBulk => user.Has(Domain.Identity.Permissions.ReportsExport);

    public async Task<Result<bool>> AuthorizeShareAsync(ShareRequest request, CancellationToken ct)
    {
        var scope = request.Scope?.Trim() ?? "";
        if (scope is not ("card" or "selection" or "list" or "pdf" or "excel" or "print") || request.Count < 1)
            return AppError.Validation("نوع المشاركة غير معروف");
        if (!(scope == "card" && request.Count == 1) && !CanShareBulk)
            return AppError.Forbidden("مشاركة أو تصدير أكثر من بطاقة غير مسموح لهذا المستخدم");
        db.Audit(user, clock, $"share.{scope}", "search", Guid.Empty,
            new { count = request.Count, query = PartyService.Clean(request.Query, 100) });
        await db.SaveChangesAsync(ct);
        return true;
    }

    /// <summary>نتائج البحث (أو المحدد منها) إلى Excel: الموردون ثم العملاء، بنفس صلاحيات العرض.</summary>
    public async Task<Result<(byte[] Content, string FileName)>> SearchAsync(SearchExportRequest request,
        CancellationToken ct)
    {
        if (!CanShareBulk)
            return AppError.Forbidden("تصدير القوائم غير مسموح لهذا المستخدم");
        var result = await search.SearchAsync(request.Q, request.MaterialId, request.ManufacturerId, request.GradeId, ct);
        var chosen = request.PartyIds is { Count: > 0 } ids ? ids.ToHashSet() : null;
        var rows = new List<IReadOnlyList<object?>>();
        foreach (var (kind, cards) in new[] { ("مورد", result.Suppliers), ("عميل", result.Customers) })
        foreach (var c in cards.Where(c => chosen is null || chosen.Contains(c.PartyId)))
        {
            var spec = c.Specs.Count > 0 ? c.Specs[0] : null;
            rows.Add([kind, c.Name, c.ContactName, c.Phone, spec?.MaterialCode, spec?.ManufacturerName,
                spec?.GradeCode, spec?.OriginName, c.Exact ? "مطابقة دقيقة" : "بديل محتمل", string.Join("، ", c.Reasons)]);
        }
        db.Audit(user, clock, "export.search", "search", Guid.Empty,
            new { count = rows.Count, query = PartyService.Clean(request.Q, 100) });
        await db.SaveChangesAsync(ct);
        var content = XlsxWriter.Write("نتائج البحث",
            ["نوع السجل", "اسم الشركة", "جهة الاتصال", "الهاتف", "الخامة", "الشركة المصنّعة", "Grade", "بلد الصنع",
                "نتيجة المطابقة", "السبب"], rows);
        return (content, $"search-{clock.GetUtcNow():yyyyMMdd-HHmm}.xlsx");
    }
    private const int MaxRows = 10_000;

    public async Task<Result<(byte[] Content, string FileName)>> PartiesAsync(string role, CancellationToken ct)
    {
        var supplier = role == "supplier";
        if (role is not ("customer" or "supplier"))
            return AppError.Validation("حدد العملاء أو الموردين");
        if (supplier && !access.CanSeeSuppliers)
            return AppError.Forbidden();
        if (!CanShareBulk)
            return AppError.Forbidden("تصدير القوائم غير مسموح لهذا المستخدم");

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
