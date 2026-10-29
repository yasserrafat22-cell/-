using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Reference;

public sealed record GradeFileDto(Guid Id, Guid GradeId, GradeFileKind Kind, string FileName, string ContentType,
    long SizeBytes, DateTimeOffset CreatedAt);

/// <summary>
/// صورة الـ Grade (صورة فقط) وملف المواصفات (PDF فقط) في الكتالوج الموحد.
/// أول ملف من كل نوع يضيفه أي مستخدم مسجِّل؛ الاستبدال والحذف للمدير العام فقط.
/// </summary>
public sealed class GradeFileService(IAppDbContext db, ICurrentUser user, IFileStore store, TimeProvider clock)
{
    private bool CanManage => user.Has(Permissions.RecordsManage);

    private bool CanAdd => CanManage || user.Has(Permissions.MasterDataManage)
        || user.Has(Permissions.CustomersCreate) || user.Has(Permissions.SuppliersCreate);

    public async Task<Result<(GradeFileDto File, bool Created)>> UploadAsync(Guid gradeId, Guid id, GradeFileKind kind,
        string? fileName, long length, Stream content, CancellationToken ct)
    {
        if (!CanAdd)
            return AppError.Forbidden();
        if (id == Guid.Empty || !Enum.IsDefined(kind))
            return AppError.Validation("بيانات الملف غير مكتملة");
        if (!await db.Grades.AnyAsync(g => g.Id == gradeId && g.IsActive, ct))
            return AppError.NotFound();

        var existing = await db.GradeFiles.AsNoTracking().FirstOrDefaultAsync(f => f.Id == id, ct);
        if (existing is not null)
            return existing.GradeId == gradeId && existing.CreatedBy == user.UserId
                ? (ToDto(existing), false)
                : AppError.Conflict("attachment.id_taken", "معرف الملف مستخدم بالفعل");

        var current = await db.GradeFiles
            .Where(f => f.GradeId == gradeId && f.Kind == kind && f.DeletedAt == null).ToListAsync(ct);
        if (current.Count > 0 && !CanManage)
            return AppError.Forbidden(kind == GradeFileKind.Photo
                ? "تغيير صورة الـ Grade بعد حفظها للمدير العام فقط"
                : "تغيير ملف المواصفات بعد حفظه للمدير العام فقط");

        var max = kind == GradeFileKind.Photo ? AttachmentService.MaxImageBytes : AttachmentService.MaxPdfBytes;
        if (length <= 0)
            return AppError.Validation("الملف فارغ", "attachment.empty");
        using var buffer = new MemoryStream();
        await AttachmentService.CopyLimitedAsync(content, buffer, max + 1, ct);
        var contentType = AttachmentService.Sniff(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 16)));
        if (contentType is null)
            return AppError.Validation("نوع الملف غير مدعوم", "attachment.unsupported");
        var isPdf = contentType == "application/pdf";
        if (kind == GradeFileKind.DataSheet != isPdf)
            return AppError.Validation(isPdf ? "صورة الـ Grade يجب أن تكون صورة" : "ملف المواصفات يجب أن يكون PDF فقط",
                "attachment.wrong_type");
        if (buffer.Length > max)
            return AppError.Validation(isPdf ? "الحد الأقصى لملف PDF هو 20MB" : "الحد الأقصى للصورة هو 10MB",
                "attachment.too_large");

        var now = clock.GetUtcNow();
        var file = new GradeFile
        {
            Id = id,
            GradeId = gradeId,
            Kind = kind,
            FileName = AttachmentService.SafeName(fileName, contentType),
            ContentType = contentType,
            SizeBytes = buffer.Length,
            Sha256 = Convert.ToHexStringLower(SHA256.HashData(buffer.GetBuffer().AsSpan(0, (int)buffer.Length))),
            StorageKey = $"{now:yyyy}/{now:MM}/{id:N}",
            CreatedAt = now,
            CreatedBy = user.UserId,
        };
        buffer.Position = 0;
        await store.SaveAsync(file.StorageKey, buffer, ct);
        foreach (var old in current)
        {
            old.DeletedAt = now;
            old.DeletedBy = user.UserId;
        }
        db.GradeFiles.Add(file);
        db.Audit(user, clock, "catalog.grade_file_added", "grade", gradeId, new { kind = kind.ToString(), name = file.FileName });
        await db.SaveChangesAsync(ct);
        return (ToDto(file), true);
    }

    /// <summary>ملفات الكتالوج متاحة لكل مستخدم مسجل الدخول (ليست بيانات مورد بعينه).</summary>
    public async Task<Result<AttachmentContent>> OpenAsync(Guid id, CancellationToken ct)
    {
        var file = await db.GradeFiles.AsNoTracking().FirstOrDefaultAsync(f => f.Id == id && f.DeletedAt == null, ct);
        if (file is null)
            return AppError.NotFound();
        var stream = store.OpenRead(file.StorageKey);
        return stream is null
            ? AppError.NotFound("محتوى الملف غير موجود على السيرفر")
            : new AttachmentContent(stream, file.ContentType, file.FileName);
    }

    public async Task<Result<bool>> RemoveAsync(Guid id, CancellationToken ct)
    {
        if (!CanManage)
            return AppError.Forbidden("حذف ملفات الكتالوج للمدير العام فقط");
        var file = await db.GradeFiles.FirstOrDefaultAsync(f => f.Id == id, ct);
        if (file is null)
            return AppError.NotFound();
        if (file.DeletedAt is null)
        {
            file.DeletedAt = clock.GetUtcNow();
            file.DeletedBy = user.UserId;
            db.Audit(user, clock, "catalog.grade_file_removed", "grade", file.GradeId, new { name = file.FileName });
            await db.SaveChangesAsync(ct);
        }
        return true;
    }

    private static GradeFileDto ToDto(GradeFile f) =>
        new(f.Id, f.GradeId, f.Kind, f.FileName, f.ContentType, f.SizeBytes, f.CreatedAt);
}
