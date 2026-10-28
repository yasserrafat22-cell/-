using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Crm;

/// <summary>
/// قواعد صلاحيات العملاء والموردين على السيرفر (قرار السؤال 1): العرض حسب
/// صلاحية الدور، والتعديل للجميع لمن يملك «تعديل الكل»، أو لسجلاته فقط
/// (التي أنشأها أو هو مندوبها) لمن يملك «تعديل الخاص».
/// </summary>
public sealed class PartyAccess(IAppDbContext db, ICurrentUser user)
{
    public bool CanView(Party party) =>
        (party.IsCustomer && user.Has(Permissions.CustomersView))
        || (party.IsSupplier && user.Has(Permissions.SuppliersView));

    public bool CanCreate(bool customer, bool supplier) =>
        (customer || supplier)
        && (!customer || user.Has(Permissions.CustomersCreate))
        && (!supplier || user.Has(Permissions.SuppliersCreate));

    public async Task<bool> CanEditAsync(Party party, CancellationToken ct)
    {
        if ((party.IsCustomer && user.Has(Permissions.CustomersEditAll))
            || (party.IsSupplier && user.Has(Permissions.SuppliersEditAll)))
            return true;

        var mayEditOwn = (party.IsCustomer && user.Has(Permissions.CustomersEditOwn))
            || (party.IsSupplier && user.Has(Permissions.SuppliersEditOwn));
        return mayEditOwn && await IsOwnAsync(party, ct);
    }

    private async Task<bool> IsOwnAsync(Party party, CancellationToken ct) =>
        party.CreatedBy == user.UserId
        || (party.RepresentativeId is { } repId
            && await db.Representatives.AnyAsync(r => r.Id == repId && r.UserId == user.UserId, ct));

    /// <summary>
    /// يحمّل الطرف إذا كان موجودًا ومسموحًا بعرضه. الطرف غير المسموح يُعامل
    /// كغير موجود حتى لا يُكشف وجوده.
    /// </summary>
    public async Task<Result<Party>> LoadVisibleAsync(Guid id, CancellationToken ct)
    {
        var party = await db.Parties.FirstOrDefaultAsync(p => p.Id == id && p.DeletedAt == null, ct);
        return party is not null && CanView(party) ? party : AppError.NotFound();
    }

    public async Task<Result<Party>> LoadEditableAsync(Guid id, CancellationToken ct)
    {
        var loaded = await LoadVisibleAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded;
        return await CanEditAsync(loaded.Value!, ct) ? loaded : AppError.Forbidden();
    }
}
