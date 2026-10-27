namespace Qadisiyah.Domain.Identity;

/// <summary>
/// كتالوج الصلاحيات التفصيلية. الأكواد ثابتة لأن الكود يعتمد عليها في فرض
/// الصلاحيات على السيرفر، أما توزيعها على الأدوار فيُدار من قاعدة البيانات.
/// </summary>
public static class Permissions
{
    public const string CustomersView = "customers.view";
    public const string CustomersCreate = "customers.create";
    public const string CustomersEditOwn = "customers.edit_own";
    public const string CustomersEditAll = "customers.edit_all";

    public const string SuppliersView = "suppliers.view";
    public const string SuppliersCreate = "suppliers.create";
    public const string SuppliersEditOwn = "suppliers.edit_own";
    public const string SuppliersEditAll = "suppliers.edit_all";

    public const string OrdersManage = "orders.manage";
    public const string SuppliesManage = "supplies.manage";
    public const string OpportunitiesManage = "opportunities.manage";

    public const string PricesView = "prices.view";
    public const string PricesManage = "prices.manage";
    public const string ProfitsView = "profits.view";

    public const string ReportsView = "reports.view";
    public const string ReportsExport = "reports.export";

    public const string MasterDataManage = "masterdata.manage";
    public const string ImportRun = "import.run";

    public const string UsersManage = "users.manage";
    public const string DevicesManage = "devices.manage";
    public const string AuditView = "audit.view";

    public static readonly IReadOnlyDictionary<string, string> Descriptions =
        new Dictionary<string, string>
        {
            [CustomersView] = "عرض العملاء",
            [CustomersCreate] = "إضافة العملاء",
            [CustomersEditOwn] = "تعديل العملاء المسؤول عنهم",
            [CustomersEditAll] = "تعديل جميع العملاء",
            [SuppliersView] = "عرض الموردين",
            [SuppliersCreate] = "إضافة الموردين",
            [SuppliersEditOwn] = "تعديل الموردين المسؤول عنهم",
            [SuppliersEditAll] = "تعديل جميع الموردين",
            [OrdersManage] = "تسجيل وتعديل الطلبات",
            [SuppliesManage] = "تسجيل وتعديل التوريدات",
            [OpportunitiesManage] = "إدارة فرص البيع",
            [PricesView] = "الاطلاع على أسعار الموردين",
            [PricesManage] = "تسجيل عروض الأسعار",
            [ProfitsView] = "الاطلاع على الأرباح",
            [ReportsView] = "عرض التقارير",
            [ReportsExport] = "استخراج التقارير PDF وExcel",
            [MasterDataManage] = "إدارة القوائم والبيانات الأساسية",
            [ImportRun] = "استيراد Excel",
            [UsersManage] = "إدارة المستخدمين والأدوار",
            [DevicesManage] = "إدارة الأجهزة وإلغاء صلاحيتها",
            [AuditView] = "الاطلاع على سجل التدقيق",
        };

    public static IReadOnlyCollection<string> All { get; } = [.. Descriptions.Keys];
}
