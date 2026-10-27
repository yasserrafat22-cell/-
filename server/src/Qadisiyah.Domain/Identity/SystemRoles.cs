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

    public sealed record Definition(string Code, string NameAr, IReadOnlyCollection<string> Permissions);

    public static readonly IReadOnlyList<Definition> Defaults =
    [
        new(SystemAdmin, "مدير النظام", Identity.Permissions.All),
        new(SalesManager, "مدير المبيعات",
        [
            Identity.Permissions.CustomersView, Identity.Permissions.CustomersCreate,
            Identity.Permissions.CustomersEditAll, Identity.Permissions.SuppliersView,
            Identity.Permissions.OrdersManage, Identity.Permissions.OpportunitiesManage,
            Identity.Permissions.PricesView, Identity.Permissions.ProfitsView,
            Identity.Permissions.ReportsView, Identity.Permissions.ReportsExport,
            Identity.Permissions.ImportRun,
        ]),
        new(PurchasingManager, "مدير المشتريات",
        [
            Identity.Permissions.SuppliersView, Identity.Permissions.SuppliersCreate,
            Identity.Permissions.SuppliersEditAll, Identity.Permissions.CustomersView,
            Identity.Permissions.SuppliesManage, Identity.Permissions.OpportunitiesManage,
            Identity.Permissions.PricesView, Identity.Permissions.PricesManage,
            Identity.Permissions.ProfitsView, Identity.Permissions.ReportsView,
            Identity.Permissions.ReportsExport, Identity.Permissions.ImportRun,
        ]),
        new(Representative, "مندوب",
        [
            Identity.Permissions.CustomersView, Identity.Permissions.CustomersCreate,
            Identity.Permissions.CustomersEditOwn, Identity.Permissions.SuppliersView,
            Identity.Permissions.SuppliersCreate, Identity.Permissions.SuppliersEditOwn,
            Identity.Permissions.OrdersManage, Identity.Permissions.SuppliesManage,
            Identity.Permissions.OpportunitiesManage, Identity.Permissions.ReportsView,
        ]),
    ];
}
