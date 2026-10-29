using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Reference;

public sealed record LookupDto(Guid Id, string Code, string NameAr, string? Semantic, string AppliesTo);

public sealed record UnitDto(Guid Id, string Code, string NameAr, decimal FactorToKg);

/// <summary>Grade في الكتالوج مع شركته وبلدان صنعه المعروفة.</summary>
public sealed record GradeDto(Guid Id, string Code, Guid? ManufacturerId = null, bool IsVerified = true,
    IReadOnlyList<Guid>? OriginIds = null, Guid? PhotoFileId = null, Guid? DataSheetFileId = null);

public sealed record ManufacturerDto(Guid Id, string Name);

public sealed record MaterialDto(Guid Id, string Code, string NameAr, string? NameEn, IReadOnlyList<GradeDto> Grades);

public sealed record RepresentativeDto(Guid Id, string Name, Guid? UserId);

/// <summary>كل القوائم الأساسية التي يحتاجها التطبيق في طلب واحد.</summary>
public sealed record ReferenceBundle(
    IReadOnlyList<LookupDto> ActivityTypes,
    IReadOnlyList<LookupDto> ContactOutcomes,
    IReadOnlyList<LookupDto> Governorates,
    IReadOnlyList<LookupDto> Currencies,
    IReadOnlyList<UnitDto> Units,
    IReadOnlyList<MaterialDto> Materials,
    IReadOnlyList<RepresentativeDto> Representatives,
    Guid? MyRepresentativeId,
    IReadOnlyList<ManufacturerDto> Manufacturers,
    IReadOnlyList<LookupDto> Countries);

public sealed record CreateMaterialRequest(string Code, string NameAr, string? NameEn);

public sealed class ReferenceService(IAppDbContext db, ICurrentUser user, TimeProvider clock)
{
    public async Task<ReferenceBundle> GetBundleAsync(CancellationToken ct)
    {
        await EnsureMyRepresentativeAsync(ct);

        var lookups = await db.LookupItems.AsNoTracking()
            .Where(l => l.IsActive)
            .OrderBy(l => l.SortOrder).ThenBy(l => l.NameAr)
            .ToListAsync(ct);
        IReadOnlyList<LookupDto> Of(string category) => lookups
            .Where(l => l.Category == category)
            .Select(l => new LookupDto(l.Id, l.Code, l.NameAr, l.Semantic, l.AppliesTo))
            .ToList();

        var units = await db.Units.AsNoTracking().Where(u => u.IsActive).OrderBy(u => u.SortOrder)
            .Select(u => new UnitDto(u.Id, u.Code, u.NameAr, u.FactorToKg)).ToListAsync(ct);

        var materials = await db.Materials.AsNoTracking().Where(m => m.IsActive)
            .OrderBy(m => m.SortOrder).ThenBy(m => m.Code)
            .Select(m => new MaterialDto(m.Id, m.Code, m.NameAr, m.NameEn,
                m.Grades.Where(g => g.IsActive).OrderBy(g => g.Code)
                    .Select(g => new GradeDto(g.Id, g.Code, g.ManufacturerId, g.IsVerified,
                        g.Origins.Select(o => o.CountryId).ToList(),
                        db.GradeFiles.Where(f => f.GradeId == g.Id && f.Kind == GradeFileKind.Photo && f.DeletedAt == null)
                            .Select(f => (Guid?)f.Id).FirstOrDefault(),
                        db.GradeFiles.Where(f => f.GradeId == g.Id && f.Kind == GradeFileKind.DataSheet && f.DeletedAt == null)
                            .Select(f => (Guid?)f.Id).FirstOrDefault()))
                    .ToList()))
            .ToListAsync(ct);

        var manufacturers = await db.Manufacturers.AsNoTracking().Where(m => m.IsActive).OrderBy(m => m.Name)
            .Select(m => new ManufacturerDto(m.Id, m.Name)).ToListAsync(ct);

        var reps = await db.Representatives.AsNoTracking().Where(r => r.IsActive).OrderBy(r => r.Name)
            .Select(r => new RepresentativeDto(r.Id, r.Name, r.UserId)).ToListAsync(ct);

        return new ReferenceBundle(
            Of(LookupCategories.ActivityType), Of(LookupCategories.ContactOutcome),
            Of(LookupCategories.Governorate), Of(LookupCategories.Currency),
            units, materials, reps,
            reps.FirstOrDefault(r => r.UserId == user.UserId)?.Id,
            manufacturers, Of(LookupCategories.Country));
    }

    /// <summary>
    /// لكل مستخدم ملف مندوب مرتبط بحسابه يُنشأ عند أول استخدام، فيُختار
    /// تلقائيًا «المندوب المسؤول» عند التسجيل.
    /// </summary>
    public async Task<Guid?> EnsureMyRepresentativeAsync(CancellationToken ct)
    {
        var existing = await db.Representatives.Where(r => r.UserId == user.UserId)
            .Select(r => new { r.Id, r.IsActive }).FirstOrDefaultAsync(ct);
        if (existing is not null)
            return existing.IsActive ? existing.Id : null;

        var name = await db.Users.Where(u => u.Id == user.UserId).Select(u => u.DisplayName).FirstOrDefaultAsync(ct);
        if (name is null)
            return null;
        var rep = new Representative { Name = name, UserId = user.UserId };
        db.Representatives.Add(rep);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // طلب متزامن أنشأه بالفعل (فهرس فريد على user_id).
            db.Representatives.Entry(rep).State = EntityState.Detached;
            return await db.Representatives.Where(r => r.UserId == user.UserId && r.IsActive)
                .Select(r => (Guid?)r.Id).FirstOrDefaultAsync(ct);
        }
        return rep.Id;
    }

    public async Task<Result<MaterialDto>> CreateMaterialAsync(CreateMaterialRequest request, CancellationToken ct)
    {
        var code = request.Code?.Trim().ToUpperInvariant() ?? "";
        if (code.Length is 0 or > 32 || string.IsNullOrWhiteSpace(request.NameAr))
            return AppError.Validation("كود الخامة واسمها العربي مطلوبان");
        if (await db.Materials.AnyAsync(m => m.Code == code, ct))
            return AppError.Conflict("material.duplicate", "هذه الخامة مسجلة بالفعل");

        var material = new Material { Code = code, NameAr = request.NameAr.Trim(), NameEn = request.NameEn?.Trim() };
        material.Aliases.Add(new MaterialAlias { Alias = code, Normalized = TextNormalizer.NormalizeCode(code) });
        db.Materials.Add(material);
        db.Audit(user, clock, "masterdata.material_created", "material", material.Id, new { code });
        await db.SaveChangesAsync(ct);
        return new MaterialDto(material.Id, material.Code, material.NameAr, material.NameEn, []);
    }
}
