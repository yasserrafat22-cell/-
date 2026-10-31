using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Reference;

/// <summary>المعرف اختياري يولده التطبيق (يتيح الإضافة دون اتصال وإعادة الإرسال دون تكرار).</summary>
public sealed record CreateManufacturerRequest(string Name, Guid? Id = null);

/// <summary>نوع خامة أساسي (PP، ABS، PA...) مستقل عن الـ Grade التجاري.</summary>
public sealed record CreateMaterialTypeRequest(string Code, string? NameAr = null, string? NameEn = null, Guid? Id = null);

public sealed record UpdateManufacturerRequest(string Name, bool IsActive = true);

/// <summary>
/// إضافة Grade. <see cref="ConfirmSimilar"/> يؤكد الإضافة رغم وجود نفس الكود
/// لشركة أخرى أو بشركة غير محددة (بعد عرضها على المستخدم).
/// </summary>
/// <param name="ManufacturerId">اختياري: الشركة لا تُخمَّن؛ Grade بلا شركة يبقى «الشركة غير محددة».</param>
public sealed record CreateGradeRequest(
    Guid MaterialId,
    Guid? ManufacturerId,
    string Code,
    IReadOnlyList<Guid>? OriginIds = null,
    string? Description = null,
    bool ConfirmSimilar = false,
    Guid? Id = null);

/// <summary>تعديل Grade من المدير، ومنه ربط Grade قديم بشركته يدويًا.</summary>
public sealed record UpdateGradeRequest(
    Guid? ManufacturerId,
    string Code,
    IReadOnlyList<Guid>? OriginIds = null,
    string? Description = null,
    bool IsActive = true);

public sealed record CreateCountryRequest(string Code, string NameAr);

/// <summary>Grade كما يظهر في شاشة الكتالوج للإدارة.</summary>
public sealed record CatalogGradeDto(
    Guid Id,
    Guid MaterialId,
    string MaterialCode,
    string Code,
    Guid? ManufacturerId,
    string? ManufacturerName,
    IReadOnlyList<Guid> OriginIds,
    string? Description,
    bool IsVerified,
    bool IsActive,
    string? CreatedByName,
    DateTimeOffset? CreatedAt,
    Guid? PhotoFileId = null,
    Guid? DataSheetFileId = null);

public sealed record CatalogManufacturerDto(Guid Id, string Name, bool IsActive, int GradeCount);

/// <summary>
/// الكتالوج الموحد للشركات المصنّعة والـ Grades وبلدان الصنع. أي مستخدم مصرح له
/// يضيف وتظهر الإضافة فورًا؛ التعديل والإيقاف للمدير. الـ Grades القديمة
/// «بانتظار التحقق» المتعارضة تبقى للمدير يراجعها. لا يوجد حذف؛ الإيقاف فقط حتى تبقى
/// السجلات القديمة مرتبطة.
/// </summary>
public sealed class CatalogService(IAppDbContext db, ICurrentUser user, TimeProvider clock)
{
    private const int MaxOrigins = 10;

    private bool IsAdmin => user.Has(Permissions.MasterDataManage);

    private bool CanRegister => IsAdmin
        || user.Has(Permissions.CustomersCreate) || user.Has(Permissions.SuppliersCreate)
        || user.Has(Permissions.OrdersManage) || user.Has(Permissions.SuppliesManage);

    public async Task<Result<IReadOnlyList<CatalogManufacturerDto>>> ListManufacturersAsync(CancellationToken ct)
    {
        if (!IsAdmin)
            return AppError.Forbidden();
        return await db.Manufacturers.AsNoTracking().OrderBy(m => m.Name)
            .Select(m => new CatalogManufacturerDto(m.Id, m.Name, m.IsActive,
                db.Grades.Count(g => g.ManufacturerId == m.Id)))
            .ToListAsync(ct);
    }

    /// <summary>يعيد الشركة الموجودة بنفس الاسم بعد التطبيع بدل إنشاء نسخة ثانية.</summary>
    public async Task<Result<(ManufacturerDto Manufacturer, bool Created)>> CreateManufacturerAsync(
        CreateManufacturerRequest request, CancellationToken ct)
    {
        if (!CanRegister)
            return AppError.Forbidden();
        var name = request.Name?.Trim() ?? "";
        var normalized = TextNormalizer.Normalize(name);
        if (normalized.Length is 0 or > 120)
            return AppError.Validation("اسم الشركة المصنّعة مطلوب (حتى 120 حرفًا)");

        // إعادة إرسال نفس العملية، أو نفس الاسم من جهاز آخر: يُعاد الموجود (والتطبيق يربط معرفه به).
        var existing = await db.Manufacturers.AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == request.Id || m.NormalizedName == normalized, ct);
        if (existing is not null)
            return (new ManufacturerDto(existing.Id, existing.Name), false);

        var manufacturer = new Manufacturer { Name = name, NormalizedName = normalized };
        if (request.Id is { } id && id != Guid.Empty)
            manufacturer.Id = id;
        db.Manufacturers.Add(manufacturer);
        db.Audit(user, clock, "masterdata.manufacturer_created", "manufacturer", manufacturer.Id, new { name });
        await db.SaveChangesAsync(ct);
        return (new ManufacturerDto(manufacturer.Id, manufacturer.Name), true);
    }

    /// <summary>
    /// إضافة نوع خامة أساسي دون مصنع أو Grade (لا يُنشأ Grade وهمي). الاختصار والاسم الكامل
    /// يُطابقان الموجود فلا تتكرر الخامة. الإضافة لمن يسجل بيانات، والتعديل والحذف للمدير.
    /// </summary>
    public async Task<Result<(MaterialDto Material, bool Created)>> CreateMaterialTypeAsync(
        CreateMaterialTypeRequest request, CancellationToken ct)
    {
        if (!CanRegister)
            return AppError.Forbidden();
        var code = request.Code?.Trim().ToUpperInvariant() ?? "";
        if (code.Length is 0 or > 32)
            return AppError.Validation("اختصار الخامة مطلوب (مثل PP أو ABS)");
        var keys = new[] { code, request.NameEn, request.NameAr }
            .Where(k => !string.IsNullOrWhiteSpace(k)).Select(TextNormalizer.NormalizeCode).Distinct().ToList();
        var existing = await db.Materials.AsNoTracking()
            .Where(m => m.Id == request.Id || m.Code == code || m.Aliases.Any(a => keys.Contains(a.Normalized)))
            .FirstOrDefaultAsync(ct);
        if (existing is not null)
            return (new MaterialDto(existing.Id, existing.Code, existing.NameAr, existing.NameEn, []), false);

        var material = new Material
        {
            Code = code,
            NameAr = string.IsNullOrWhiteSpace(request.NameAr) ? code : request.NameAr.Trim(),
            NameEn = string.IsNullOrWhiteSpace(request.NameEn) ? null : request.NameEn.Trim(),
            SortOrder = 1000,
        };
        if (request.Id is { } id && id != Guid.Empty)
            material.Id = id;
        foreach (var alias in new[] { code, material.NameEn, request.NameAr }.Where(a => !string.IsNullOrWhiteSpace(a))
                     .DistinctBy(a => TextNormalizer.NormalizeCode(a)))
            material.Aliases.Add(new MaterialAlias { Alias = alias!.Trim(), Normalized = TextNormalizer.NormalizeCode(alias) });
        db.Materials.Add(material);
        db.Audit(user, clock, "masterdata.material_created", "material", material.Id, new { code });
        await db.SaveChangesAsync(ct);
        return (new MaterialDto(material.Id, material.Code, material.NameAr, material.NameEn, []), true);
    }

    public async Task<Result<ManufacturerDto>> UpdateManufacturerAsync(Guid id, UpdateManufacturerRequest request,
        CancellationToken ct)
    {
        if (!IsAdmin)
            return AppError.Forbidden();
        var manufacturer = await db.Manufacturers.FirstOrDefaultAsync(m => m.Id == id, ct);
        if (manufacturer is null)
            return AppError.NotFound();
        var name = request.Name?.Trim() ?? "";
        var normalized = TextNormalizer.Normalize(name);
        if (normalized.Length is 0 or > 120)
            return AppError.Validation("اسم الشركة المصنّعة مطلوب (حتى 120 حرفًا)");
        if (await db.Manufacturers.AnyAsync(m => m.NormalizedName == normalized && m.Id != id, ct))
            return AppError.Conflict("catalog.duplicate_manufacturer", "توجد شركة مسجلة بنفس الاسم");

        db.Audit(user, clock, "masterdata.manufacturer_updated", "manufacturer", id,
            new { from = manufacturer.Name, to = name, request.IsActive });
        manufacturer.Name = name;
        manufacturer.NormalizedName = normalized;
        manufacturer.IsActive = request.IsActive;
        await db.SaveChangesAsync(ct);
        return new ManufacturerDto(manufacturer.Id, manufacturer.Name);
    }

    public async Task<Result<IReadOnlyList<CatalogGradeDto>>> ListGradesAsync(Guid? materialId, bool pendingOnly,
        CancellationToken ct)
    {
        if (!IsAdmin)
            return AppError.Forbidden();
        var grades = db.Grades.AsNoTracking().AsQueryable();
        if (materialId is { } m)
            grades = grades.Where(g => g.MaterialId == m);
        if (pendingOnly)
            grades = grades.Where(g => !g.IsVerified && g.IsActive);
        return await Project(grades).ToListAsync(ct);
    }

    public async Task<Result<(CatalogGradeDto Grade, bool Created)>> CreateGradeAsync(CreateGradeRequest request,
        CancellationToken ct)
    {
        if (!CanRegister)
            return AppError.Forbidden();
        var code = request.Code?.Trim() ?? "";
        var normalized = TextNormalizer.NormalizeCode(code);
        if (normalized.Length == 0 || code.Length > 64)
            return AppError.Validation("كود الـ Grade مطلوب (حتى 64 حرفًا)");
        if (!await db.Materials.AnyAsync(m => m.Id == request.MaterialId && m.IsActive, ct))
            return AppError.Validation("خامة غير معروفة");
        if (request.ManufacturerId is { } makerId && !await db.Manufacturers.AnyAsync(m => m.Id == makerId && m.IsActive, ct))
            return AppError.Validation("الشركة المصنّعة غير معروفة");
        var origins = await ValidateOriginsAsync(request.OriginIds, ct);
        if (!origins.IsSuccess)
            return origins.Error!;

        if (request.Id is { } replay && await db.Grades.AnyAsync(g => g.Id == replay, ct))
            return (await GetGradeAsync(replay, ct), false);

        var sameCode = await db.Grades.AsNoTracking()
            .Where(g => g.MaterialId == request.MaterialId && g.NormalizedCode == normalized)
            .Select(g => g.Id).ToListAsync(ct);
        var exact = await db.Grades.AsNoTracking().Where(g => sameCode.Contains(g.Id) && g.ManufacturerId == request.ManufacturerId)
            .Select(g => (Guid?)g.Id).FirstOrDefaultAsync(ct);
        if (exact is { } existingId)
            return (await GetGradeAsync(existingId, ct), false);
        if (sameCode.Count > 0 && !request.ConfirmSimilar)
        {
            var similar = await Project(db.Grades.AsNoTracking().Where(g => sameCode.Contains(g.Id))).ToListAsync(ct);
            return AppError.Conflict("catalog.similar_grade",
                "يوجد Grade بنفس الكود لشركة أخرى أو بشركة غير محددة. تأكد قبل الإضافة.", similar);
        }

        var grade = new Grade
        {
            MaterialId = request.MaterialId,
            ManufacturerId = request.ManufacturerId,
            Code = code,
            NormalizedCode = normalized,
            Description = Clean(request.Description, 300),
            // قرار 0.5: الإضافة من أي مستخدم مصرح له تظهر فورًا في الكتالوج المشترك دون موافقة.
            IsVerified = true,
            CreatedBy = user.UserId,
            CreatedAt = clock.GetUtcNow(),
        };
        if (request.Id is { } gradeId && gradeId != Guid.Empty)
            grade.Id = gradeId;
        grade.Origins.AddRange(origins.Value!.Select(c => new GradeOrigin { GradeId = grade.Id, CountryId = c }));
        db.Grades.Add(grade);
        db.Audit(user, clock, "masterdata.grade_created", "grade", grade.Id,
            new { request.MaterialId, request.ManufacturerId, code, verified = grade.IsVerified });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // إضافة متزامنة لنفس Grade: الفهرس الفريد يمنع النسخة الثانية.
            db.Grades.Entry(grade).State = EntityState.Detached;
            var raced = await db.Grades.AsNoTracking()
                .Where(g => g.MaterialId == request.MaterialId && g.ManufacturerId == request.ManufacturerId
                    && g.NormalizedCode == normalized)
                .Select(g => g.Id).FirstAsync(ct);
            return (await GetGradeAsync(raced, ct), false);
        }
        return (await GetGradeAsync(grade.Id, ct), true);
    }

    public async Task<Result<CatalogGradeDto>> UpdateGradeAsync(Guid id, UpdateGradeRequest request, CancellationToken ct)
    {
        if (!IsAdmin)
            return AppError.Forbidden();
        var grade = await db.Grades.Include(g => g.Origins).FirstOrDefaultAsync(g => g.Id == id, ct);
        if (grade is null)
            return AppError.NotFound();
        var code = request.Code?.Trim() ?? "";
        var normalized = TextNormalizer.NormalizeCode(code);
        if (normalized.Length == 0 || code.Length > 64)
            return AppError.Validation("كود الـ Grade مطلوب (حتى 64 حرفًا)");
        if (request.ManufacturerId is { } maker && !await db.Manufacturers.AnyAsync(m => m.Id == maker, ct))
            return AppError.Validation("الشركة المصنّعة غير معروفة");
        if (grade.ManufacturerId is not null && request.ManufacturerId is null)
            return AppError.Validation("لا يمكن إلغاء الشركة المصنّعة لـ Grade مرتبط بشركة");
        var origins = await ValidateOriginsAsync(request.OriginIds, ct);
        if (!origins.IsSuccess)
            return origins.Error!;
        if (await db.Grades.AnyAsync(g => g.Id != id && g.MaterialId == grade.MaterialId
                && g.ManufacturerId == request.ManufacturerId && g.NormalizedCode == normalized, ct))
            return AppError.Conflict("catalog.duplicate_grade", "يوجد Grade بنفس الكود لنفس الشركة والخامة");

        db.Audit(user, clock, "masterdata.grade_updated", "grade", id, new
        {
            from = new { grade.Code, grade.ManufacturerId },
            to = new { code, request.ManufacturerId },
            request.IsActive,
        });
        grade.Code = code;
        grade.NormalizedCode = normalized;
        grade.ManufacturerId = request.ManufacturerId;
        grade.Description = Clean(request.Description, 300);
        grade.IsActive = request.IsActive;
        grade.Origins.RemoveAll(o => !origins.Value!.Contains(o.CountryId));
        foreach (var country in origins.Value!.Where(c => grade.Origins.All(o => o.CountryId != c)))
            grade.Origins.Add(new GradeOrigin { GradeId = grade.Id, CountryId = country });
        await db.SaveChangesAsync(ct);
        return await GetGradeAsync(id, ct);
    }

    public async Task<Result<CatalogGradeDto>> VerifyGradeAsync(Guid id, CancellationToken ct)
    {
        if (!IsAdmin)
            return AppError.Forbidden();
        var grade = await db.Grades.FirstOrDefaultAsync(g => g.Id == id, ct);
        if (grade is null)
            return AppError.NotFound();
        if (grade.ManufacturerId is null)
            return AppError.Validation("حدد الشركة المصنّعة قبل اعتماد الـ Grade");
        if (!grade.IsVerified)
        {
            grade.IsVerified = true;
            db.Audit(user, clock, "masterdata.grade_verified", "grade", id, null);
            await db.SaveChangesAsync(ct);
        }
        return await GetGradeAsync(id, ct);
    }

    public async Task<Result<LookupDto>> CreateCountryAsync(CreateCountryRequest request, CancellationToken ct)
    {
        if (!IsAdmin)
            return AppError.Forbidden();
        var code = request.Code?.Trim().ToUpperInvariant() ?? "";
        var name = request.NameAr?.Trim() ?? "";
        if (code.Length != 2 || !code.All(char.IsAsciiLetterUpper) || name.Length is 0 or > 100)
            return AppError.Validation("كود البلد حرفان (مثل SA) والاسم العربي مطلوب");
        if (await db.LookupItems.AnyAsync(l => l.Category == LookupCategories.Country && l.Code == code, ct))
            return AppError.Conflict("catalog.duplicate_country", "هذا البلد مسجل بالفعل");
        var item = new LookupItem
        {
            Category = LookupCategories.Country,
            Code = code,
            NameAr = name,
            SortOrder = 1000,
        };
        db.LookupItems.Add(item);
        db.Audit(user, clock, "masterdata.country_created", "lookup", item.Id, new { code, name });
        await db.SaveChangesAsync(ct);
        return new LookupDto(item.Id, item.Code, item.NameAr, null, item.AppliesTo);
    }

    private async Task<Result<List<Guid>>> ValidateOriginsAsync(IReadOnlyList<Guid>? ids, CancellationToken ct)
    {
        var list = (ids ?? []).Distinct().ToList();
        if (list.Count > MaxOrigins)
            return AppError.Validation($"الحد الأقصى {MaxOrigins} بلدان للـ Grade");
        var known = await db.LookupItems.CountAsync(l => list.Contains(l.Id) && l.Category == LookupCategories.Country, ct);
        return known == list.Count ? list : AppError.Validation("بلد الصنع غير معروف", "spec.unknown_country");
    }

    private async Task<CatalogGradeDto> GetGradeAsync(Guid id, CancellationToken ct) =>
        await Project(db.Grades.AsNoTracking().Where(g => g.Id == id)).FirstAsync(ct);

    private IQueryable<CatalogGradeDto> Project(IQueryable<Grade> grades) =>
        from g in grades
        join mat in db.Materials on g.MaterialId equals mat.Id
        join m in db.Manufacturers on g.ManufacturerId equals m.Id into makers
        from m in makers.DefaultIfEmpty()
        join u in db.Users on g.CreatedBy equals u.Id into creators
        from u in creators.DefaultIfEmpty()
        orderby mat.Code, m == null ? "" : m.Name, g.Code
        select new CatalogGradeDto(g.Id, g.MaterialId, mat.Code, g.Code, g.ManufacturerId, m == null ? null : m.Name,
            g.Origins.Select(o => o.CountryId).ToList(), g.Description, g.IsVerified, g.IsActive,
            u == null ? null : u.DisplayName, g.CreatedAt,
            db.GradeFiles.Where(f => f.GradeId == g.Id && f.Kind == GradeFileKind.Photo && f.DeletedAt == null)
                .Select(f => (Guid?)f.Id).FirstOrDefault(),
            db.GradeFiles.Where(f => f.GradeId == g.Id && f.Kind == GradeFileKind.DataSheet && f.DeletedAt == null)
                .Select(f => (Guid?)f.Id).FirstOrDefault());

    private static string? Clean(string? value, int max) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim() is var t && t.Length > max ? t[..max] : value.Trim();
}
