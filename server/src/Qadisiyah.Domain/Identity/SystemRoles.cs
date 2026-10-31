namespace Qadisiyah.Domain.Identity;

/// <summary>
/// الأدوار المبدئية المعتمدة (قرار T9) وصلاحياتها الافتراضية عند الإنشاء.
/// يمكن تعديل صلاحيات أي دور لاحقًا من إدارة المستخدمين.
/// </summary>
public static class SystemRoles
{
    public const string SystemAdmin = "system_admin";
    public const string SalesManager = "sales_manager";
    public const string PurchasingManager = "purchasing_manager";
    public const string Representative = "representative";
    public const string Secretary = "secretary";

    public sealed record Definition(string Code, string NameAr, IReadOnlyCollection<string> Permissions);

    /// <summary>
    /// السكرتارية: اطلاع كامل على العملاء والموردين، وإضافة واختيار المسؤول والتاريخ
    /// عند الإنشاء، بلا تعديل أو حذف بعد الحفظ.
    /// </summary>
    public static readonly IReadOnlyCollection<string> OfficePermissions =
    [
        Identity.Permissions.CustomersViewAll, Identity.Permissions.SuppliersViewAll,
        Identity.Permissions.RecordsAssign, Identity.Permissions.TeamAssign,
        Identity.Permissions.CustomersView, Identity.Permissions.CustomersCreate,
        Identity.Permissions.SuppliersView, Identity.Permissions.SuppliersCreate,
        Identity.Permissions.OrdersManage, Identity.Permissions.SuppliesManage,
        Identity.Permissions.PricesView, Identity.Permissions.ReportsView, Identity.Permissions.ReportsExport,
        Identity.Permissions.ImportRun,
    ];

    /// <summary>مدير المبيعات: كل العملاء والمبيعات وفريقه، دون أي اطلاع على الموردين.</summary>
    public static readonly IReadOnlyCollection<string> SalesManagerPermissions =
    [
        Identity.Permissions.CustomersViewAll, Identity.Permissions.RecordsAssign, Identity.Permissions.TeamAssign,
        Identity.Permissions.CustomersView, Identity.Permissions.CustomersCreate, Identity.Permissions.SuppliersCreate,
        Identity.Permissions.OrdersManage, Identity.Permissions.OpportunitiesManage,
        Identity.Permissions.ReportsView, Identity.Permissions.ReportsExport, Identity.Permissions.ImportRun,
    ];

    /// <summary>مدير المشتريات: كل الموردين والمشتريات وفريقه، والعملاء التابعون له فقط.</summary>
    public static readonly IReadOnlyCollection<string> PurchasingManagerPermissions =
    [
        Identity.Permissions.SuppliersViewAll, Identity.Permissions.RecordsAssign, Identity.Permissions.TeamAssign,
        Identity.Permissions.CustomersView, Identity.Permissions.CustomersCreate,
        Identity.Permissions.SuppliersView, Identity.Permissions.SuppliersCreate,
        Identity.Permissions.SuppliesManage, Identity.Permissions.OrdersManage,
        Identity.Permissions.PricesView, Identity.Permissions.PricesManage,
        Identity.Permissions.ReportsView, Identity.Permissions.ReportsExport, Identity.Permissions.ImportRun,
    ];

    public static readonly IReadOnlyList<Definition> Defaults =
    [
        new(SystemAdmin, "مدير النظام", Identity.Permissions.All),
        new(SalesManager, "مدير المبيعات", SalesManagerPermissions),
        new(PurchasingManager, "مدير المشتريات", PurchasingManagerPermissions),
        new(Secretary, "سكرتارية", OfficePermissions),
        // المندوب يضيف عملاء وموردين لكنه يرى عملاءه فقط ولا يرى أي مورد.
        new(Representative, "مندوب",
        [
            Identity.Permissions.CustomersView, Identity.Permissions.CustomersCreate,
            Identity.Permissions.SuppliersCreate, Identity.Permissions.OrdersManage,
            Identity.Permissions.OpportunitiesManage, Identity.Permissions.ReportsView,
        ]),
    ];

    /// <summary>
    /// صلاحيات جديدة تُضاف مرة واحدة للأدوار الموجودة عند الترقية (إضافة فقط،
    /// لا تُحذف صلاحية موجودة). الإصدار يُحفظ في الإعدادات حتى لا تُكرر.
    /// </summary>
    public static readonly IReadOnlyList<(int Version, string Role, IReadOnlyCollection<string> Permissions)> UpgradeGrants =
    [
        (2, SystemAdmin,
        [
            Identity.Permissions.CustomersViewAll, Identity.Permissions.SuppliersViewAll,
            Identity.Permissions.RecordsManage, Identity.Permissions.RecordsAssign,
            Identity.Permissions.BackupManage, Identity.Permissions.TeamAssign,
        ]),
        (2, SalesManager, SalesManagerPermissions),
        (2, PurchasingManager, PurchasingManagerPermissions),
        // تسجيل العملاء الجديد: السكرتارية تُسند العملاء للمندوبين.
        (3, Secretary, [Identity.Permissions.TeamAssign]),
    ];
}
