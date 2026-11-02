using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Role> Roles => Set<Role>();
    public DbSet<UserRole> UserRoles => Set<UserRole>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<AuditEntry> AuditEntries => Set<AuditEntry>();

    public DbSet<LookupItem> LookupItems => Set<LookupItem>();
    public DbSet<Unit> Units => Set<Unit>();
    public DbSet<Material> Materials => Set<Material>();
    public DbSet<MaterialAlias> MaterialAliases => Set<MaterialAlias>();
    public DbSet<Grade> Grades => Set<Grade>();
    public DbSet<Manufacturer> Manufacturers => Set<Manufacturer>();
    public DbSet<CustomerActivity> CustomerActivities => Set<CustomerActivity>();
    public DbSet<PartyCustomerActivity> PartyCustomerActivities => Set<PartyCustomerActivity>();
    public DbSet<GradeOrigin> GradeOrigins => Set<GradeOrigin>();
    public DbSet<Representative> Representatives => Set<Representative>();
    public DbSet<AppSetting> AppSettings => Set<AppSetting>();

    public DbSet<Party> Parties => Set<Party>();
    public DbSet<PartyPhone> PartyPhones => Set<PartyPhone>();
    public DbSet<UserFavorite> UserFavorites => Set<UserFavorite>();
    public DbSet<PartyLocation> PartyLocations => Set<PartyLocation>();
    public DbSet<PartyContact> PartyContacts => Set<PartyContact>();
    public DbSet<GradeFile> GradeFiles => Set<GradeFile>();
    public DbSet<ImportBatch> ImportBatches => Set<ImportBatch>();
    public DbSet<ImportEntry> ImportEntries => Set<ImportEntry>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<CustomerInterest> CustomerInterests => Set<CustomerInterest>();
    public DbSet<SupplierProduct> SupplierProducts => Set<SupplierProduct>();
    public DbSet<PriceQuote> PriceQuotes => Set<PriceQuote>();
    public DbSet<Interaction> Interactions => Set<Interaction>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderLine> OrderLines => Set<OrderLine>();
    public DbSet<OrderStageChange> OrderStageChanges => Set<OrderStageChange>();
    public DbSet<Supply> Supplies => Set<Supply>();
    public DbSet<SupplyLine> SupplyLines => Set<SupplyLine>();

    public void SetOriginalVersion<T>(T entity, uint version) where T : class =>
        Entry(entity).Property("Version").OriginalValue = version;

    public Task ReloadAsync<T>(T entity, CancellationToken ct) where T : class => Entry(entity).ReloadAsync(ct);

    public Task<Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction> BeginTransactionAsync(CancellationToken ct) =>
        Database.BeginTransactionAsync(ct);

    public Task<List<ImportEntry>> LockImportEntriesAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct)
    {
        var list = ids.ToArray();
        return ImportEntries.FromSqlInterpolated($"SELECT * FROM import_entries WHERE id = ANY({list}) ORDER BY id FOR UPDATE")
            .ToListAsync(ct);
    }

    public async Task RecountImportBatchesAsync(IReadOnlyCollection<Guid> batchIds, CancellationToken ct)
    {
        var ids = batchIds.Distinct().OrderBy(i => i).ToArray();
        if (ids.Length == 0)
            return;
        var own = Database.CurrentTransaction is null;
        var tx = own ? await Database.BeginTransactionAsync(ct) : null;
        try
        {
            // قفل صفوف الدفعات أولًا (بترتيب ثابت)، ثم العد بلقطة جديدة بعد الحصول على القفل.
            await Database.ExecuteSqlInterpolatedAsync(
                $"SELECT id FROM import_batches WHERE id = ANY({ids}) ORDER BY id FOR UPDATE", ct);
            await Database.ExecuteSqlInterpolatedAsync($"""
                UPDATE import_batches b SET
                    created_count = c.created, pending_count = c.pending,
                    duplicate_count = c.duplicate, failed_count = c.failed,
                    summary = json_build_object('createdCount', c.created, 'pendingCount', c.pending,
                        'duplicateCount', c.duplicate, 'failedCount', c.failed)::text
                FROM (
                    SELECT b2.id,
                        count(e.id) FILTER (WHERE e.status = 'completed') AS created,
                        count(e.id) FILTER (WHERE e.status = 'pending') AS pending,
                        count(e.id) FILTER (WHERE e.status = 'duplicate') AS duplicate,
                        count(e.id) FILTER (WHERE e.status = 'failed') AS failed
                    FROM import_batches b2 LEFT JOIN import_entries e ON e.batch_id = b2.id
                    WHERE b2.id = ANY({ids})
                    GROUP BY b2.id
                ) c
                WHERE b.id = c.id
                """, ct);
            if (tx is not null)
                await tx.CommitAsync(ct);
        }
        finally
        {
            if (tx is not null)
                await tx.DisposeAsync();
        }
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(b =>
        {
            b.ToTable("users");
            b.Property(u => u.Username).HasMaxLength(64);
            b.HasIndex(u => u.Username).IsUnique();
            b.Property(u => u.DisplayName).HasMaxLength(150);
            b.HasMany(u => u.Roles).WithOne().HasForeignKey(ur => ur.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Role>(b =>
        {
            b.ToTable("roles");
            b.Property(r => r.Code).HasMaxLength(64);
            b.HasIndex(r => r.Code).IsUnique();
            b.Property(r => r.NameAr).HasMaxLength(100);
            b.HasMany(r => r.Permissions).WithOne().HasForeignKey(p => p.RoleId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserRole>(b =>
        {
            b.ToTable("user_roles");
            b.HasKey(ur => new { ur.UserId, ur.RoleId });
            b.HasOne(ur => ur.Role).WithMany().HasForeignKey(ur => ur.RoleId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<RolePermission>(b =>
        {
            b.ToTable("role_permissions");
            b.HasKey(rp => new { rp.RoleId, rp.Permission });
            b.Property(rp => rp.Permission).HasMaxLength(64);
        });

        modelBuilder.Entity<Device>(b =>
        {
            b.ToTable("devices");
            b.Property(d => d.Id).ValueGeneratedNever();
            b.Property(d => d.Name).HasMaxLength(100);
            b.Property(d => d.RevokeReason).HasMaxLength(500);
            b.Ignore(d => d.IsRevoked);
        });

        modelBuilder.Entity<RefreshToken>(b =>
        {
            b.ToTable("refresh_tokens");
            b.Property(t => t.TokenHash).HasMaxLength(64);
            b.HasIndex(t => t.TokenHash).IsUnique();
            b.HasIndex(t => t.FamilyId);
            b.HasIndex(t => new { t.UserId, t.RevokedAt });
            b.HasIndex(t => new { t.DeviceId, t.RevokedAt });
            b.HasOne<User>().WithMany().HasForeignKey(t => t.UserId).OnDelete(DeleteBehavior.Cascade);
            b.HasOne<Device>().WithMany().HasForeignKey(t => t.DeviceId).OnDelete(DeleteBehavior.Cascade);
            // عمود xmin في PostgreSQL يمنع نجاح تحديثين متزامنين لنفس الرمز.
            b.Property<uint>("xmin").HasColumnType("xid").ValueGeneratedOnAddOrUpdate().IsConcurrencyToken();
        });

        modelBuilder.Entity<AuditEntry>(b =>
        {
            b.ToTable("audit_log");
            b.Property(a => a.Action).HasMaxLength(64);
            b.Property(a => a.EntityType).HasMaxLength(64);
            b.Property(a => a.Data).HasColumnType("jsonb");
            b.Property(a => a.IpAddress).HasMaxLength(64);
            b.HasIndex(a => a.At);
            b.HasIndex(a => new { a.EntityType, a.EntityId });
            b.HasIndex(a => a.UserId);
        });

        CrmModel.Configure(modelBuilder);
    }
}
