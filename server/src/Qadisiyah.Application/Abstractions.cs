using Microsoft.EntityFrameworkCore;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application;

public interface IAppDbContext
{
    DbSet<User> Users { get; }
    DbSet<Role> Roles { get; }
    DbSet<UserRole> UserRoles { get; }
    DbSet<RolePermission> RolePermissions { get; }
    DbSet<Device> Devices { get; }
    DbSet<RefreshToken> RefreshTokens { get; }
    DbSet<AuditEntry> AuditEntries { get; }

    DbSet<LookupItem> LookupItems { get; }
    DbSet<Unit> Units { get; }
    DbSet<Material> Materials { get; }
    DbSet<MaterialAlias> MaterialAliases { get; }
    DbSet<Grade> Grades { get; }
    DbSet<Manufacturer> Manufacturers { get; }
    DbSet<CustomerActivity> CustomerActivities { get; }
    DbSet<PartyCustomerActivity> PartyCustomerActivities { get; }
    DbSet<GradeOrigin> GradeOrigins { get; }
    DbSet<Representative> Representatives { get; }
    DbSet<AppSetting> AppSettings { get; }

    DbSet<Party> Parties { get; }
    DbSet<PartyPhone> PartyPhones { get; }
    DbSet<UserFavorite> UserFavorites { get; }
    DbSet<PartyLocation> PartyLocations { get; }
    DbSet<PartyContact> PartyContacts { get; }
    DbSet<GradeFile> GradeFiles { get; }
    DbSet<ImportBatch> ImportBatches { get; }
    DbSet<ImportEntry> ImportEntries { get; }
    DbSet<Attachment> Attachments { get; }
    DbSet<CustomerInterest> CustomerInterests { get; }
    DbSet<SupplierProduct> SupplierProducts { get; }
    DbSet<PriceQuote> PriceQuotes { get; }
    DbSet<Interaction> Interactions { get; }
    DbSet<Order> Orders { get; }
    DbSet<OrderLine> OrderLines { get; }
    DbSet<OrderStageChange> OrderStageChanges { get; }
    DbSet<Supply> Supplies { get; }
    DbSet<SupplyLine> SupplyLines { get; }

    /// <summary>يحدد رقم النسخة الذي قرأه العميل لكشف التعديل المتزامن.</summary>
    void SetOriginalVersion<T>(T entity, uint version) where T : class;

    /// <summary>يعيد قراءة كيان متتبع من قاعدة البيانات (بعد تعارض متزامن) ويجعله غير معدل.</summary>
    Task ReloadAsync<T>(T entity, CancellationToken ct) where T : class;

    /// <summary>معاملة صريحة تجمع عدة عمليات حفظ (تُلغى كلها إن لم تُعتمد).</summary>
    Task<Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction> BeginTransactionAsync(CancellationToken ct);

    /// <summary>
    /// يقفل صفوف «الإدخال السريع» المحددة للتعديل حتى نهاية المعاملة الحالية (SELECT ... FOR UPDATE)
    /// ويعيدها متتبعة بقيمها الحالية في قاعدة البيانات.
    /// </summary>
    Task<List<ImportEntry>> LockImportEntriesAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct);

    /// <summary>
    /// يعيد حساب عدادات الدفعات من حالات صفوفها في قاعدة البيانات، بعد قفل صفوف الدفعات حتى لا تتداخل
    /// عمليتا إعادة حساب متزامنتان على قيم قديمة.
    /// </summary>
    Task RecountImportBatchesAsync(IReadOnlyCollection<Guid> batchIds, CancellationToken ct);

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string hash, string password);
}

public sealed record AccessTokenClaims(
    Guid UserId,
    string Username,
    Guid DeviceId,
    Guid SecurityStamp,
    bool MustChangePassword,
    IReadOnlyCollection<string> Roles,
    IReadOnlyCollection<string> Permissions);

public interface IAccessTokenIssuer
{
    (string Token, DateTimeOffset ExpiresAt) Issue(AccessTokenClaims claims);
}
