using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;

namespace Qadisiyah.Application.Crm;

/// <summary>جهة اتصال جديدة أو تعديلها. المعرف يولده التطبيق (إعادة الإرسال لا تكرر).</summary>
public sealed record ContactInput(
    Guid Id,
    string Name,
    string? JobTitle = null,
    string? Mobile = null,
    bool IsPrimary = false,
    uint Version = 0);

public sealed record ContactDto(Guid Id, Guid PartyId, string Name, string? JobTitle, string? Mobile, bool IsPrimary,
    uint Version);

/// <summary>موظفو الشركة وجهات الاتصال: الإضافة لمن يرى السجل، والتعديل والحذف للمدير العام.</summary>
public sealed class ContactService(IAppDbContext db, ICurrentUser user, PartyAccess access, TimeProvider clock)
{
    private const int MaxContacts = 50;

    public async Task<Result<IReadOnlyList<ContactDto>>> ListAsync(Guid partyId, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        return await db.PartyContacts.AsNoTracking()
            .Where(c => c.PartyId == partyId && c.DeletedAt == null)
            .OrderByDescending(c => c.IsPrimary).ThenBy(c => c.CreatedAt)
            .Select(c => ToDto(c))
            .ToListAsync(ct);
    }

    public async Task<Result<ContactDto>> CreateAsync(Guid partyId, ContactInput input, CancellationToken ct)
    {
        var loaded = await access.LoadForAddAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var existing = await db.PartyContacts.AsNoTracking().FirstOrDefaultAsync(c => c.Id == input.Id, ct);
        if (existing is not null)
            return existing.PartyId == partyId && existing.CreatedBy == user.UserId
                ? ToDto(existing)
                : AppError.Conflict("contact.id_taken", "معرف جهة الاتصال مستخدم بالفعل");

        var (mobile, error) = Validate(input);
        if (error is not null)
            return error;
        var count = await db.PartyContacts.CountAsync(c => c.PartyId == partyId && c.DeletedAt == null, ct);
        if (count >= MaxContacts)
            return AppError.Validation($"الحد الأقصى {MaxContacts} جهة اتصال");

        var contact = new PartyContact { Id = input.Id, PartyId = partyId, Name = "" };
        Apply(contact, input, mobile);
        // أول جهة اتصال أساسية تلقائيًا؛ نقل «الأساسية» لاحقًا تعديل لبيانات محفوظة (للمدير).
        contact.IsPrimary = count == 0 || (input.IsPrimary && access.CanManage);
        contact.Stamp(user.UserId, clock.GetUtcNow());
        if (contact.IsPrimary)
            await ClearPrimaryAsync(partyId, ct);
        db.PartyContacts.Add(contact);
        db.Audit(user, clock, "party.contact_added", "party", partyId, new { name = contact.Name });
        await db.SaveChangesAsync(ct);
        return ToDto(contact);
    }

    public async Task<Result<ContactDto>> UpdateAsync(Guid id, ContactInput input, CancellationToken ct)
    {
        var contact = await db.PartyContacts.FirstOrDefaultAsync(c => c.Id == id && c.DeletedAt == null, ct);
        if (contact is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(contact.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (contact.Version != input.Version)
            return AppError.StaleVersion();
        var (mobile, error) = Validate(input);
        if (error is not null)
            return error;
        if (input.IsPrimary && !contact.IsPrimary)
            await ClearPrimaryAsync(contact.PartyId, ct);
        db.SetOriginalVersion(contact, input.Version);
        Apply(contact, input, mobile);
        contact.IsPrimary = input.IsPrimary;
        contact.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "party.contact_updated", "party", contact.PartyId, new { name = contact.Name });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return AppError.StaleVersion();
        }
        return ToDto(contact);
    }

    public async Task<Result<bool>> RemoveAsync(Guid id, CancellationToken ct)
    {
        var contact = await db.PartyContacts.FirstOrDefaultAsync(c => c.Id == id, ct);
        if (contact is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(contact.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (contact.DeletedAt is null)
        {
            var now = clock.GetUtcNow();
            contact.DeletedAt = now;
            contact.IsPrimary = false;
            contact.Touch(user.UserId, now);
            db.Audit(user, clock, "party.contact_removed", "party", contact.PartyId, new { name = contact.Name });
            await db.SaveChangesAsync(ct);
        }
        return true;
    }

    private async Task ClearPrimaryAsync(Guid partyId, CancellationToken ct)
    {
        var current = await db.PartyContacts.Where(c => c.PartyId == partyId && c.IsPrimary && c.DeletedAt == null)
            .ToListAsync(ct);
        if (current.Count == 0)
            return;
        foreach (var c in current)
            c.IsPrimary = false;
        await db.SaveChangesAsync(ct);
    }

    private static (string? Mobile, AppError? Error) Validate(ContactInput input)
    {
        if (input.Id == Guid.Empty || string.IsNullOrWhiteSpace(input.Name) || input.Name.Trim().Length < 2)
            return (null, AppError.Validation("اكتب اسم جهة الاتصال"));
        if (string.IsNullOrWhiteSpace(input.Mobile))
            return (null, null);
        var mobile = PhoneNumber.Normalize(input.Mobile);
        return mobile is null
            ? (null, AppError.Validation($"رقم الهاتف غير صحيح: {input.Mobile}", "party.invalid_phone"))
            : (mobile, null);
    }

    private static void Apply(PartyContact contact, ContactInput input, string? mobile)
    {
        contact.Name = PartyService.Clean(input.Name, 150)!;
        contact.JobTitle = PartyService.Clean(input.JobTitle, 100);
        contact.Mobile = mobile;
    }

    private static ContactDto ToDto(PartyContact c) =>
        new(c.Id, c.PartyId, c.Name, c.JobTitle, c.Mobile, c.IsPrimary, c.Version);
}
