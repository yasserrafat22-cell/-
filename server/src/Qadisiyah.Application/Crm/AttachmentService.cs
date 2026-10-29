using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

public sealed record AttachmentUpload(
    Guid Id,
    AttachmentKind Kind,
    string? FileName,
    long Length,
    Stream Content,
    Guid? GradeId = null,
    Guid? MaterialId = null,
    string? Caption = null);

public sealed record AttachmentDto(
    Guid Id,
    Guid PartyId,
    AttachmentKind Kind,
    Guid? MaterialId,
    Guid? GradeId,
    SpecInfo? Spec,
    string FileName,
    string ContentType,
    long SizeBytes,
    string? Caption,
    DateTimeOffset CreatedAt,
    string? CreatedByName);

public sealed record AttachmentContent(Stream Content, string ContentType, string FileName);

/// <summary>
/// المرفقات: شعار، صور منتجات، ملفات TDS، ومرفقات أخرى. نوع الملف يُحدد من
/// محتواه لا من اسمه، والحجم محدود (صورة 10MB، PDF 20MB).
/// </summary>
public sealed class AttachmentService(
    IAppDbContext db,
    ICurrentUser user,
    PartyAccess access,
    MaterialSpecs specs,
    IFileStore store,
    TimeProvider clock)
{
    public const long MaxImageBytes = 10 * 1024 * 1024;
    public const long MaxPdfBytes = 20 * 1024 * 1024;
    private const int MaxPerParty = 200;

    private static readonly Dictionary<string, string> Extensions = new()
    {
        ["image/jpeg"] = ".jpg",
        ["image/png"] = ".png",
        ["image/webp"] = ".webp",
        ["application/pdf"] = ".pdf",
    };

    public async Task<Result<IReadOnlyList<AttachmentDto>>> ListAsync(Guid partyId, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var rows = await (
            from a in db.Attachments.AsNoTracking()
            where a.PartyId == partyId && a.DeletedAt == null
            join u in db.Users on a.CreatedBy equals u.Id into us
            from u in us.DefaultIfEmpty()
            orderby a.CreatedAt descending
            select new { a, UserName = u == null ? null : u.DisplayName })
            .ToListAsync(ct);
        return await ToDtosAsync(rows.Select(r => (r.a, (string?)r.UserName)).ToList(), ct);
    }

    public async Task<Result<(AttachmentDto Attachment, bool Created)>> UploadAsync(Guid partyId, AttachmentUpload upload,
        CancellationToken ct)
    {
        var loaded = await access.LoadForAddAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (upload.Kind == AttachmentKind.Logo && !access.CanManage
            && await db.Attachments.AnyAsync(a => a.PartyId == partyId && a.Kind == AttachmentKind.Logo && a.DeletedAt == null, ct))
            return AppError.Forbidden("تغيير الشعار بعد حفظه للمدير العام فقط");
        if (upload.Id == Guid.Empty || !Enum.IsDefined(upload.Kind))
            return AppError.Validation("بيانات الملف غير مكتملة");

        var existing = await db.Attachments.AsNoTracking().FirstOrDefaultAsync(a => a.Id == upload.Id, ct);
        if (existing is not null)
            return existing.PartyId == partyId && existing.CreatedBy == user.UserId
                ? ((await ToDtosAsync([(existing, null)], ct))[0], false)
                : AppError.Conflict("attachment.id_taken", "معرف الملف مستخدم بالفعل");

        // ربط TDS والصور بالخامة/الـ Grade الصحيح.
        Guid? gradeId = null, materialId = null;
        if (upload.Kind == AttachmentKind.TechnicalDataSheet)
        {
            if (!party.IsSupplier || !access.CanSeeSuppliers)
                return AppError.Validation("ملفات TDS تُضاف للموردين فقط", "attachment.tds_supplier_only");
            if (upload.GradeId is null)
                return AppError.Validation("حدد الخامة والشركة والـ Grade لملف TDS", "attachment.tds_needs_grade");
        }
        if (upload.Kind is AttachmentKind.TechnicalDataSheet or AttachmentKind.ProductPhoto)
        {
            if (upload.GradeId is { } g)
            {
                var grade = await db.Grades.AsNoTracking().FirstOrDefaultAsync(x => x.Id == g && x.IsActive, ct);
                if (grade is null)
                    return AppError.Validation("الـ Grade غير معروف", "spec.unknown_grade");
                if (upload.Kind == AttachmentKind.TechnicalDataSheet && grade.ManufacturerId is null)
                    return AppError.Validation("حدد الشركة المصنّعة لهذا الـ Grade أولًا من الكتالوج",
                        "attachment.tds_needs_manufacturer");
                if (upload.MaterialId is { } m && m != grade.MaterialId)
                    return AppError.Validation("الـ Grade لا يتبع نوع الخامة المختار", "spec.grade_material_mismatch");
                (gradeId, materialId) = (grade.Id, grade.MaterialId);
            }
            else if (upload.MaterialId is { } m)
            {
                if (!await db.Materials.AnyAsync(x => x.Id == m, ct))
                    return AppError.Validation("خامة غير معروفة");
                materialId = m;
            }
        }

        if (upload.Length <= 0)
            return AppError.Validation("الملف فارغ", "attachment.empty");
        if (upload.Length > MaxPdfBytes)
            return AppError.Validation("حجم الملف أكبر من المسموح (20MB لملف PDF و10MB للصورة)", "attachment.too_large");
        if (await db.Attachments.CountAsync(a => a.PartyId == partyId && a.DeletedAt == null, ct) >= MaxPerParty)
            return AppError.Validation($"الحد الأقصى {MaxPerParty} ملفًا لكل سجل");

        // يُقرأ الملف مرة واحدة: النوع من أول البايتات، والبصمة، والحجم الفعلي.
        using var buffer = new MemoryStream();
        await CopyLimitedAsync(upload.Content, buffer, MaxPdfBytes + 1, ct);
        if (buffer.Length == 0)
            return AppError.Validation("الملف فارغ", "attachment.empty");
        var contentType = Sniff(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 16)));
        if (contentType is null)
            return AppError.Validation("نوع الملف غير مدعوم. المسموح: صور JPG/PNG/WEBP أو PDF", "attachment.unsupported");
        var isPdf = contentType == "application/pdf";
        var allowed = upload.Kind switch
        {
            AttachmentKind.Logo or AttachmentKind.ProductPhoto => !isPdf,
            AttachmentKind.TechnicalDataSheet => isPdf,
            _ => true,
        };
        if (!allowed)
            return AppError.Validation(isPdf ? "هذا النوع يقبل الصور فقط" : "ملف TDS يجب أن يكون PDF",
                "attachment.wrong_type");
        if (buffer.Length > (isPdf ? MaxPdfBytes : MaxImageBytes))
            return AppError.Validation(isPdf ? "الحد الأقصى لملف PDF هو 20MB" : "الحد الأقصى للصورة هو 10MB",
                "attachment.too_large");

        var now = clock.GetUtcNow();
        var attachment = new Attachment
        {
            Id = upload.Id,
            PartyId = partyId,
            Kind = upload.Kind,
            GradeId = gradeId,
            MaterialId = materialId,
            FileName = SafeName(upload.FileName, contentType),
            ContentType = contentType,
            SizeBytes = buffer.Length,
            Sha256 = Convert.ToHexStringLower(SHA256.HashData(buffer.GetBuffer().AsSpan(0, (int)buffer.Length))),
            StorageKey = $"{now:yyyy}/{now:MM}/{upload.Id:N}",
            Caption = PartyService.Clean(upload.Caption, 200),
            CreatedAt = now,
            CreatedBy = user.UserId,
        };

        buffer.Position = 0;
        await store.SaveAsync(attachment.StorageKey, buffer, ct);

        if (upload.Kind == AttachmentKind.Logo)
        {
            // الشعار الجديد يحل محل السابق؛ القديم يبقى محفوظًا (حذف منطقي).
            var oldLogos = await db.Attachments
                .Where(a => a.PartyId == partyId && a.Kind == AttachmentKind.Logo && a.DeletedAt == null)
                .ToListAsync(ct);
            foreach (var old in oldLogos)
            {
                old.DeletedAt = now;
                old.DeletedBy = user.UserId;
            }
        }
        db.Attachments.Add(attachment);
        db.Audit(user, clock, "party.attachment_added", "party", partyId, new { name = attachment.FileName });
        await db.SaveChangesAsync(ct);
        return ((await ToDtosAsync([(attachment, null)], ct))[0], true);
    }

    public async Task<Result<AttachmentContent>> OpenAsync(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.AsNoTracking().FirstOrDefaultAsync(a => a.Id == id && a.DeletedAt == null, ct);
        if (attachment is null || !(await access.LoadVisibleAsync(attachment.PartyId, ct)).IsSuccess)
            return AppError.NotFound();
        var stream = store.OpenRead(attachment.StorageKey);
        return stream is null
            ? AppError.NotFound("محتوى الملف غير موجود على السيرفر")
            : new AttachmentContent(stream, attachment.ContentType, attachment.FileName);
    }

    public async Task<Result<bool>> RemoveAsync(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.FirstOrDefaultAsync(a => a.Id == id, ct);
        if (attachment is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(attachment.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (attachment.DeletedAt is null)
        {
            attachment.DeletedAt = clock.GetUtcNow();
            attachment.DeletedBy = user.UserId;
            db.Audit(user, clock, "party.attachment_removed", "party", attachment.PartyId, new { name = attachment.FileName });
            await db.SaveChangesAsync(ct);
        }
        return true;
    }

    public async Task<Result<bool>> RestoreAsync(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.FirstOrDefaultAsync(a => a.Id == id, ct);
        if (attachment is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(attachment.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (attachment.DeletedAt is not null)
        {
            if (attachment.Kind == AttachmentKind.Logo)
            {
                // شعار واحد فعّال: المستعاد يحل محل الحالي.
                var current = await db.Attachments.Where(a => a.PartyId == attachment.PartyId
                    && a.Kind == AttachmentKind.Logo && a.DeletedAt == null).ToListAsync(ct);
                foreach (var c in current)
                {
                    c.DeletedAt = clock.GetUtcNow();
                    c.DeletedBy = user.UserId;
                }
            }
            attachment.DeletedAt = null;
            attachment.DeletedBy = null;
            db.Audit(user, clock, "party.attachment_restored", "party", attachment.PartyId, new { name = attachment.FileName });
            await db.SaveChangesAsync(ct);
        }
        return true;
    }

    private async Task<List<AttachmentDto>> ToDtosAsync(List<(Attachment A, string? UserName)> rows, CancellationToken ct)
    {
        var describe = await specs.DescribeAsync(rows.Where(r => r.A.MaterialId is not null)
            .Select(r => new ResolvedSpec(r.A.MaterialId!.Value, r.A.GradeId, null, false)), ct);
        return rows.Select(r => new AttachmentDto(r.A.Id, r.A.PartyId, r.A.Kind, r.A.MaterialId, r.A.GradeId,
            r.A.MaterialId is { } m ? describe(new ResolvedSpec(m, r.A.GradeId, null, false)) : null,
            r.A.FileName, r.A.ContentType, r.A.SizeBytes, r.A.Caption, r.A.CreatedAt, r.UserName)).ToList();
    }

    internal static async Task CopyLimitedAsync(Stream source, Stream target, long limit, CancellationToken ct)
    {
        var chunk = new byte[81920];
        long total = 0;
        int read;
        while ((read = await source.ReadAsync(chunk, ct)) > 0)
        {
            total += read;
            await target.WriteAsync(chunk.AsMemory(0, read), ct);
            if (total >= limit)
                return;
        }
    }

    /// <summary>نوع الملف من أول البايتات (لا يُعتمد على الامتداد أو ما يرسله الجهاز).</summary>
    internal static string? Sniff(ReadOnlySpan<byte> head) =>
        head switch
        {
            [0xFF, 0xD8, 0xFF, ..] => "image/jpeg",
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ..] => "image/png",
            [(byte)'R', (byte)'I', (byte)'F', (byte)'F', _, _, _, _, (byte)'W', (byte)'E', (byte)'B', (byte)'P', ..] => "image/webp",
            [(byte)'%', (byte)'P', (byte)'D', (byte)'F', (byte)'-', ..] => "application/pdf",
            _ => null,
        };

    internal static string SafeName(string? name, string contentType)
    {
        var baseName = Path.GetFileNameWithoutExtension(Path.GetFileName(name ?? ""));
        baseName = new string(baseName.Where(c => !char.IsControl(c) && c is not ('/' or '\\' or '"')).ToArray()).Trim();
        if (baseName.Length == 0)
            baseName = "file";
        if (baseName.Length > 150)
            baseName = baseName[..150];
        return baseName + Extensions[contentType];
    }
}
