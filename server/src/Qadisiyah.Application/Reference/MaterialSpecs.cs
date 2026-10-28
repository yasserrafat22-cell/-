using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Reference;

/// <summary>
/// مواصفات الخامة الموحدة في الاهتمامات والمنتجات وبنود الطلبات والتوريدات:
/// النوع إلزامي، والـ Grade (ومعه الشركة) وبلد الصنع اختياريان.
/// <see cref="OpenSpec"/> تعني «أي شركة وأي Grade مقبول»، وتختلف عن ترك الـ Grade فارغًا («غير محدد»).
/// <see cref="GradeCode"/> للتوافق مع نسخ التطبيق السابقة فقط.
/// </summary>
public sealed record SpecInput(
    Guid MaterialId,
    Guid? GradeId = null,
    Guid? OriginCountryId = null,
    bool OpenSpec = false,
    string? GradeCode = null);

public sealed record ResolvedSpec(Guid MaterialId, Guid? GradeId, Guid? OriginCountryId, bool OpenSpec);

/// <summary>دقة المواصفات كما تُعرض وتُستخدم في البحث.</summary>
public static class SpecPrecision
{
    /// <summary>Grade محدد من شركة معروفة.</summary>
    public const string Exact = "exact";

    /// <summary>Grade محدد لكن شركته غير معروفة (بيانات سابقة).</summary>
    public const string UnknownManufacturer = "unknownManufacturer";

    /// <summary>النوع فقط ولم يُحدد الـ Grade.</summary>
    public const string Unspecified = "unspecified";

    /// <summary>العميل يقبل أي شركة وأي Grade.</summary>
    public const string Open = "open";
}

public sealed record SpecInfo(
    string MaterialCode,
    string? GradeCode,
    Guid? ManufacturerId,
    string? ManufacturerName,
    Guid? OriginCountryId,
    string? OriginName,
    bool OpenSpec,
    bool GradeVerified,
    string Precision);

public sealed class MaterialSpecs(IAppDbContext db, ICurrentUser user, TimeProvider clock)
{
    public async Task<Result<ResolvedSpec>> ResolveAsync(SpecInput input, bool allowOpen, CancellationToken ct)
    {
        if (!await db.Materials.AnyAsync(m => m.Id == input.MaterialId && m.IsActive, ct))
            return AppError.Validation("خامة غير معروفة");
        if (input.OpenSpec && !allowOpen)
            return AppError.Validation("المواصفات المفتوحة متاحة لطلبات العملاء فقط", "spec.open_not_allowed");
        if (input.OpenSpec && (input.GradeId is not null || !string.IsNullOrWhiteSpace(input.GradeCode)))
            return AppError.Validation("المواصفات المفتوحة لا تحدد شركة أو Grade", "spec.open_with_grade");

        Guid? gradeId = null;
        if (input.GradeId is { } id)
        {
            var grade = await db.Grades.AsNoTracking().FirstOrDefaultAsync(g => g.Id == id, ct);
            if (grade is null || !grade.IsActive)
                return AppError.Validation("الـ Grade غير معروف", "spec.unknown_grade");
            if (grade.MaterialId != input.MaterialId)
                return AppError.Validation("الـ Grade لا يتبع نوع الخامة المختار", "spec.grade_material_mismatch");
            gradeId = grade.Id;
        }
        else if (!input.OpenSpec)
        {
            gradeId = (await ResolveLegacyCodeAsync(input.MaterialId, input.GradeCode, ct))?.Id;
        }

        if (input.OriginCountryId is { } origin
            && !await db.LookupItems.AnyAsync(l => l.Id == origin && l.Category == LookupCategories.Country && l.IsActive, ct))
            return AppError.Validation("بلد الصنع غير معروف", "spec.unknown_country");

        return new ResolvedSpec(input.MaterialId, gradeId, input.OriginCountryId, input.OpenSpec);
    }

    /// <summary>
    /// نسخ التطبيق السابقة ترسل كود الـ Grade نصًا: يُستخدم Grade بنفس الكود
    /// دون شركة إن وُجد، أو الوحيد بهذا الكود، وإلا يُنشأ «بانتظار التحقق» دون شركة.
    /// </summary>
    private async Task<Grade?> ResolveLegacyCodeAsync(Guid materialId, string? gradeCode, CancellationToken ct)
    {
        var normalized = TextNormalizer.NormalizeCode(gradeCode);
        if (normalized.Length == 0)
            return null;

        var matches = db.Grades.Local.Where(g => g.MaterialId == materialId && g.NormalizedCode == normalized).ToList();
        if (matches.Count == 0)
            matches = await db.Grades.Where(g => g.MaterialId == materialId && g.NormalizedCode == normalized).ToListAsync(ct);
        var match = matches.FirstOrDefault(g => g.ManufacturerId is null) ?? (matches.Count == 1 ? matches[0] : null);
        if (match is not null)
            return match;

        var grade = new Grade
        {
            MaterialId = materialId,
            Code = gradeCode!.Trim(),
            NormalizedCode = normalized,
            IsVerified = user.Has(Domain.Identity.Permissions.MasterDataManage),
            CreatedBy = user.UserId,
            CreatedAt = clock.GetUtcNow(),
        };
        db.Grades.Add(grade);
        db.Audit(user, clock, "masterdata.grade_created", "grade", grade.Id, new { materialId, code = grade.Code });
        return grade;
    }

    /// <summary>يحمّل أسماء الخامات والـ Grades والشركات والبلدان لمجموعة مواصفات في استعلامات قليلة.</summary>
    public async Task<Func<ResolvedSpec, SpecInfo>> DescribeAsync(IEnumerable<ResolvedSpec> specs, CancellationToken ct)
    {
        var list = specs.ToList();
        var materialIds = list.Select(s => s.MaterialId).ToHashSet();
        var gradeIds = list.Select(s => s.GradeId).OfType<Guid>().ToHashSet();
        var materials = await db.Materials.AsNoTracking().Where(m => materialIds.Contains(m.Id))
            .ToDictionaryAsync(m => m.Id, m => m.Code, ct);
        var grades = await (
            from g in db.Grades.AsNoTracking()
            where gradeIds.Contains(g.Id)
            join m in db.Manufacturers.AsNoTracking() on g.ManufacturerId equals m.Id into makers
            from m in makers.DefaultIfEmpty()
            select new { g.Id, g.Code, g.ManufacturerId, Maker = m == null ? null : m.Name, g.IsVerified })
            .ToDictionaryAsync(g => g.Id, ct);
        var originIds = list.Select(s => s.OriginCountryId).OfType<Guid>().ToHashSet();
        var origins = await db.LookupItems.AsNoTracking().Where(l => originIds.Contains(l.Id))
            .ToDictionaryAsync(l => l.Id, l => l.NameAr, ct);

        return spec =>
        {
            var grade = spec.GradeId is { } g ? grades.GetValueOrDefault(g) : null;
            var precision = spec.OpenSpec ? SpecPrecision.Open
                : grade is null ? SpecPrecision.Unspecified
                : grade.ManufacturerId is null ? SpecPrecision.UnknownManufacturer
                : SpecPrecision.Exact;
            return new SpecInfo(
                materials.GetValueOrDefault(spec.MaterialId, "?"),
                grade?.Code, grade?.ManufacturerId, grade?.Maker,
                spec.OriginCountryId, spec.OriginCountryId is { } o ? origins.GetValueOrDefault(o) : null,
                spec.OpenSpec, grade?.IsVerified ?? true, precision);
        };
    }
}
