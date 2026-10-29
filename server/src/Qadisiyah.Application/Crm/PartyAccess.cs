using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application.Crm;

/// <summary>
/// صلاحيات العملاء والموردين على السيرفر، لكل سجل:
/// <list type="bullet">
/// <item>العملاء: «الاطلاع على كل العملاء» (المدير، السكرتارية، مدير المبيعات)، وغيرهم يرى
/// العملاء الذين أنشأهم أو أُسندوا إليه فقط.</item>
/// <item>الموردون: «سجل الموردين» (المدير، السكرتارية، مدير المشتريات) فقط؛ غيرهم لا يرى أي مورد
/// حتى لو أضافه بنفسه.</item>
/// <item>الإضافة (موقع، ملاحظة، تواصل، ملف، جهة اتصال...) لمن يرى السجل ويملك صلاحية الإضافة.</item>
/// <item>تعديل أو حذف أو استعادة أي بيانات محفوظة: المدير العام فقط.</item>
/// </list>
/// السجل غير المسموح يُعامل كغير موجود حتى لا يُكشف وجوده.
/// </summary>
public sealed class PartyAccess(IAppDbContext db, ICurrentUser user)
{
    public bool ViewAllCustomers => user.Has(Permissions.CustomersViewAll);

    /// <summary>يرى كل العملاء والموردين (المدير والسكرتارية): لتقارير جودة البيانات والتكرارات.</summary>
    public bool ViewAll => ViewAllCustomers && CanSeeSuppliers;

    public bool CanManage => user.Has(Permissions.RecordsManage);

    /// <summary>اختيار المسؤول وتاريخ السجل عند الإنشاء.</summary>
    public bool CanAssign => CanManage || user.Has(Permissions.RecordsAssign);

    /// <summary>الاطلاع على بيانات الموردين (السجل، التوريدات، المنتجات، الأسعار).</summary>
    public bool CanSeeSuppliers => user.Has(Permissions.SuppliersViewAll);

    public bool CanCreate(bool customer, bool supplier) =>
        (customer || supplier)
        && (!customer || user.Has(Permissions.CustomersCreate))
        && (!supplier || user.Has(Permissions.SuppliersCreate));

    /// <summary>العملاء والموردون الظاهرون للمستخدم الحالي (للقوائم والبحث).</summary>
    public IQueryable<Party> Visible(IQueryable<Party> parties) => VisibleAs(parties, customers: true, suppliers: true);

    /// <summary>
    /// السجلات الظاهرة بدور معين: <paramref name="customers"/> = كعملاء ظاهرين للمستخدم،
    /// <paramref name="suppliers"/> = كموردين (لمن يرى سجل الموردين فقط).
    /// </summary>
    public IQueryable<Party> VisibleAs(IQueryable<Party> parties, bool customers, bool suppliers)
    {
        var uid = user.UserId;
        var allCustomers = ViewAllCustomers;
        suppliers &= CanSeeSuppliers;
        return parties.Where(p =>
            (customers && p.IsCustomer && (allCustomers
                || p.CreatedBy == uid || db.Representatives.Any(r => r.Id == p.RepresentativeId && r.UserId == uid)))
            || (suppliers && p.IsSupplier));
    }

    public async Task<bool> CanViewAsync(Party party, CancellationToken ct) =>
        ViewAll || (party.IsSupplier && CanSeeSuppliers) || (party.IsCustomer && await CanSeeCustomerSideAsync(party, ct));

    /// <summary>جانب «العميل» لشركة (لمدير المشتريات: عملاؤه فقط حتى لو رأى الشركة كمورد).</summary>
    public async Task<bool> CanSeeCustomerSideAsync(Party party, CancellationToken ct) =>
        ViewAllCustomers || await IsOwnAsync(party, ct);

    private async Task<bool> IsOwnAsync(Party party, CancellationToken ct) =>
        party.CreatedBy == user.UserId
        || (party.RepresentativeId is { } repId
            && await db.Representatives.AnyAsync(r => r.Id == repId && r.UserId == user.UserId, ct));

    public async Task<Result<Party>> LoadVisibleAsync(Guid id, CancellationToken ct)
    {
        var party = await db.Parties.FirstOrDefaultAsync(p => p.Id == id && p.DeletedAt == null, ct);
        return party is not null && await CanViewAsync(party, ct) ? party : AppError.NotFound();
    }

    /// <summary>إضافة عنصر جديد لسجل محفوظ (لا تعديل للموجود).</summary>
    public async Task<Result<Party>> LoadForAddAsync(Guid id, CancellationToken ct)
    {
        var loaded = await LoadVisibleAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded;
        var party = loaded.Value!;
        var mayAdd = (party.IsCustomer && user.Has(Permissions.CustomersCreate) && await CanSeeCustomerSideAsync(party, ct))
            || (party.IsSupplier && CanSeeSuppliers && user.Has(Permissions.SuppliersCreate))
            || CanManage;
        return mayAdd ? loaded : AppError.Forbidden();
    }

    /// <summary>تعديل أو حذف بيانات محفوظة: المدير العام فقط.</summary>
    public async Task<Result<Party>> LoadEditableAsync(Guid id, CancellationToken ct)
    {
        var loaded = await LoadVisibleAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded;
        return CanManage ? loaded : AppError.Forbidden("تعديل أو حذف البيانات المحفوظة للمدير العام فقط");
    }

    /// <summary>للمدير: السجل حتى لو كان محذوفًا (للاستعادة).</summary>
    public async Task<Result<Party>> LoadAnyForManageAsync(Guid id, CancellationToken ct)
    {
        if (!CanManage)
            return AppError.Forbidden("تعديل أو حذف البيانات المحفوظة للمدير العام فقط");
        var party = await db.Parties.FirstOrDefaultAsync(p => p.Id == id, ct);
        return party is null ? AppError.NotFound() : party;
    }

    public Task<bool> CanEditAsync(Party party, CancellationToken ct) => Task.FromResult(CanManage);
}
