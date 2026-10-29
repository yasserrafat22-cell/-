using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Infrastructure.Persistence;

/// <summary>جداول البيانات الأساسية والعملاء والموردين والأنشطة (المرحلة 3).</summary>
internal static class CrmModel
{
    public static void Configure(ModelBuilder model)
    {
        model.Entity<LookupItem>(b =>
        {
            b.ToTable("lookup_items");
            b.Property(l => l.Category).HasMaxLength(32);
            b.Property(l => l.Code).HasMaxLength(64);
            b.Property(l => l.NameAr).HasMaxLength(100);
            b.Property(l => l.NameEn).HasMaxLength(100);
            b.Property(l => l.Semantic).HasMaxLength(32);
            b.Property(l => l.AppliesTo).HasMaxLength(16);
            b.HasIndex(l => new { l.Category, l.Code }).IsUnique();
        });

        model.Entity<Unit>(b =>
        {
            b.ToTable("units");
            b.Property(u => u.Code).HasMaxLength(32);
            b.Property(u => u.NameAr).HasMaxLength(50);
            b.Property(u => u.FactorToKg).HasPrecision(18, 6);
            b.HasIndex(u => u.Code).IsUnique();
        });

        model.Entity<Material>(b =>
        {
            b.ToTable("materials");
            b.Property(m => m.Code).HasMaxLength(32);
            b.Property(m => m.NameAr).HasMaxLength(100);
            b.Property(m => m.NameEn).HasMaxLength(100);
            b.HasIndex(m => m.Code).IsUnique();
            b.HasMany(m => m.Aliases).WithOne().HasForeignKey(a => a.MaterialId).OnDelete(DeleteBehavior.Cascade);
            b.HasMany(m => m.Grades).WithOne().HasForeignKey(g => g.MaterialId).OnDelete(DeleteBehavior.Restrict);
        });

        model.Entity<MaterialAlias>(b =>
        {
            b.ToTable("material_aliases");
            b.Property(a => a.Alias).HasMaxLength(64);
            b.Property(a => a.Normalized).HasMaxLength(64);
            b.HasIndex(a => a.Normalized);
        });

        model.Entity<Manufacturer>(b =>
        {
            b.ToTable("manufacturers");
            b.Property(m => m.Name).HasMaxLength(120);
            b.Property(m => m.NormalizedName).HasMaxLength(120);
            b.HasIndex(m => m.NormalizedName).IsUnique();
        });

        model.Entity<Grade>(b =>
        {
            b.ToTable("grades");
            b.Property(g => g.Code).HasMaxLength(64);
            b.Property(g => g.NormalizedCode).HasMaxLength(64);
            b.Property(g => g.Description).HasMaxLength(300);
            b.Property(g => g.IsVerified).HasDefaultValue(true);
            b.HasOne<Manufacturer>().WithMany().HasForeignKey(g => g.ManufacturerId).OnDelete(DeleteBehavior.Restrict);
            // نفس الكود لنفس الخامة مسموح لشركتين مختلفتين فقط. NULLS NOT DISTINCT
            // يمنع أيضًا تكرار نفس الكود مرتين بشركة «غير محددة».
            b.HasIndex(g => new { g.MaterialId, g.ManufacturerId, g.NormalizedCode })
                .IsUnique().AreNullsDistinct(false).HasDatabaseName("ux_grades_material_manufacturer_code");
            b.HasIndex(g => g.NormalizedCode);
            b.HasMany(g => g.Origins).WithOne().HasForeignKey(o => o.GradeId).OnDelete(DeleteBehavior.Cascade);
        });

        model.Entity<GradeOrigin>(b =>
        {
            b.ToTable("grade_origins");
            b.HasKey(o => new { o.GradeId, o.CountryId });
            b.HasOne<LookupItem>().WithMany().HasForeignKey(o => o.CountryId).OnDelete(DeleteBehavior.Restrict);
        });

        model.Entity<Representative>(b =>
        {
            b.ToTable("representatives");
            b.Property(r => r.Name).HasMaxLength(150);
            b.Property(r => r.Phone).HasMaxLength(20);
            b.HasIndex(r => r.UserId).IsUnique().HasFilter("user_id IS NOT NULL");
        });

        model.Entity<AppSetting>(b =>
        {
            b.ToTable("app_settings");
            b.HasKey(s => s.Key);
            b.Property(s => s.Key).HasMaxLength(64);
            b.Property(s => s.Value).HasMaxLength(200);
        });

        model.Entity<Party>(b =>
        {
            b.ToTable("parties");
            Tracked(b);
            b.Property(p => p.Name).HasMaxLength(200);
            b.Property(p => p.NormalizedName).HasMaxLength(200);
            b.Property(p => p.Email).HasMaxLength(200);
            b.Property(p => p.Notes).HasMaxLength(500);
            b.Property(p => p.CountryCode).HasMaxLength(2);
            b.Property(p => p.Region).HasMaxLength(100);
            b.Property(p => p.AddressLine).HasMaxLength(300);
            b.HasIndex(p => p.NormalizedName);
            b.HasIndex(p => p.RepresentativeId);
            b.HasOne<LookupItem>().WithMany().HasForeignKey(p => p.CustomerActivityId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<LookupItem>().WithMany().HasForeignKey(p => p.SupplierActivityId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<LookupItem>().WithMany().HasForeignKey(p => p.GovernorateId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Representative>().WithMany().HasForeignKey(p => p.RepresentativeId).OnDelete(DeleteBehavior.Restrict);
            b.HasMany(p => p.Phones).WithOne().HasForeignKey(ph => ph.PartyId).OnDelete(DeleteBehavior.Cascade);
            b.HasMany(p => p.Interests).WithOne().HasForeignKey(i => i.PartyId).OnDelete(DeleteBehavior.Cascade);
            b.HasMany(p => p.Products).WithOne().HasForeignKey(sp => sp.PartyId).OnDelete(DeleteBehavior.Restrict);
        });

        model.Entity<PartyLocation>(b =>
        {
            b.ToTable("party_locations");
            Tracked(b);
            b.Property(l => l.Kind).HasConversion<string>().HasMaxLength(16);
            b.Property(l => l.Label).HasMaxLength(100);
            b.Property(l => l.AddressLine).HasMaxLength(300);
            b.Property(l => l.MapsUrl).HasMaxLength(1000);
            b.Property(l => l.AccessNotes).HasMaxLength(300);
            b.HasOne<Party>().WithMany().HasForeignKey(l => l.PartyId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(l => l.PartyId);
            // موقع افتراضي واحد فقط لكل طرف بين المواقع غير المحذوفة.
            b.HasIndex(l => l.PartyId, "ux_party_locations_default").IsUnique()
                .HasFilter("is_default AND deleted_at IS NULL").HasDatabaseName("ux_party_locations_default");
        });

        model.Entity<Attachment>(b =>
        {
            b.ToTable("attachments");
            b.Property(a => a.Id).ValueGeneratedNever();
            b.Property(a => a.Kind).HasConversion<string>().HasMaxLength(24);
            b.Property(a => a.FileName).HasMaxLength(160);
            b.Property(a => a.ContentType).HasMaxLength(64);
            b.Property(a => a.Sha256).HasMaxLength(64);
            b.Property(a => a.StorageKey).HasMaxLength(64);
            b.Property(a => a.Caption).HasMaxLength(200);
            b.HasOne<Party>().WithMany().HasForeignKey(a => a.PartyId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Material>().WithMany().HasForeignKey(a => a.MaterialId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Grade>().WithMany().HasForeignKey(a => a.GradeId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(a => new { a.PartyId, a.Kind });
            b.HasIndex(a => a.GradeId);
        });

        model.Entity<UserFavorite>(b =>
        {
            b.ToTable("user_favorites");
            b.HasKey(f => new { f.UserId, f.PartyId });
            b.HasOne<Domain.Identity.User>().WithMany().HasForeignKey(f => f.UserId).OnDelete(DeleteBehavior.Cascade);
            b.HasOne<Party>().WithMany().HasForeignKey(f => f.PartyId).OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(f => f.PartyId);
        });

        model.Entity<PartyPhone>(b =>
        {
            b.ToTable("party_phones");
            b.Property(p => p.E164).HasMaxLength(16);
            b.Property(p => p.WhatsAppE164).HasMaxLength(16);
            b.Property(p => p.Label).HasMaxLength(50);
            b.HasIndex(p => p.E164);
        });

        model.Entity<CustomerInterest>(b =>
        {
            b.ToTable("customer_interests");
            b.Property(i => i.MonthlyQuantity).HasPrecision(18, 3);
            b.HasOne<Material>().WithMany().HasForeignKey(i => i.MaterialId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Grade>().WithMany().HasForeignKey(i => i.GradeId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Unit>().WithMany().HasForeignKey(i => i.UnitId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<LookupItem>().WithMany().HasForeignKey(i => i.OriginCountryId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(i => new { i.MaterialId, i.GradeId });
        });

        model.Entity<SupplierProduct>(b =>
        {
            b.ToTable("supplier_products");
            b.Property(p => p.Notes).HasMaxLength(500);
            b.HasOne<Material>().WithMany().HasForeignKey(p => p.MaterialId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Grade>().WithMany().HasForeignKey(p => p.GradeId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<LookupItem>().WithMany().HasForeignKey(p => p.OriginCountryId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(p => new { p.MaterialId, p.GradeId });
        });

        model.Entity<PriceQuote>(b =>
        {
            b.ToTable("price_quotes");
            b.Property(q => q.Id).ValueGeneratedNever();
            b.Property(q => q.Price).HasPrecision(18, 4);
            b.Property(q => q.Currency).HasMaxLength(3);
            b.Property(q => q.TransportNote).HasMaxLength(500);
            b.Property(q => q.TaxNote).HasMaxLength(500);
            b.Property(q => q.Notes).HasMaxLength(1000);
            b.HasOne<SupplierProduct>().WithMany().HasForeignKey(q => q.SupplierProductId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Unit>().WithMany().HasForeignKey(q => q.UnitId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(q => new { q.SupplierProductId, q.QuoteDate });
        });

        model.Entity<Interaction>(b =>
        {
            b.ToTable("interactions");
            Tracked(b);
            b.Property(i => i.Channel).HasConversion<string>().HasMaxLength(16);
            b.Property(i => i.Notes).HasMaxLength(300);
            b.HasOne<Party>().WithMany().HasForeignKey(i => i.PartyId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<LookupItem>().WithMany().HasForeignKey(i => i.OutcomeId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(i => new { i.PartyId, i.OccurredAt });
            b.HasIndex(i => i.NextFollowUpAt).HasFilter("follow_up_done = false");
        });

        model.Entity<Order>(b =>
        {
            b.ToTable("orders");
            Tracked(b);
            b.Property(o => o.Stage).HasConversion<string>().HasMaxLength(16);
            b.Property(o => o.Notes).HasMaxLength(300);
            b.HasOne<Party>().WithMany().HasForeignKey(o => o.CustomerId).OnDelete(DeleteBehavior.Restrict);
            b.HasOne<Representative>().WithMany().HasForeignKey(o => o.RepresentativeId).OnDelete(DeleteBehavior.Restrict);
            b.HasMany(o => o.Lines).WithOne().HasForeignKey(l => l.OrderId).OnDelete(DeleteBehavior.Cascade);
            b.HasOne<PartyLocation>().WithMany().HasForeignKey(o => o.DeliveryLocationId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(o => new { o.CustomerId, o.OrderDate });
        });

        model.Entity<OrderLine>(b =>
        {
            b.ToTable("order_lines");
            Line(b, l => l.MaterialId, l => l.GradeId, l => l.UnitId, l => l.OriginCountryId);
            b.Property(l => l.Quantity).HasPrecision(18, 3);
            b.Property(l => l.QuantityKg).HasPrecision(18, 3);
        });

        model.Entity<OrderStageChange>(b =>
        {
            b.ToTable("order_stage_changes");
            b.Property(c => c.FromStage).HasConversion<string>().HasMaxLength(16);
            b.Property(c => c.ToStage).HasConversion<string>().HasMaxLength(16);
            b.HasOne<Order>().WithMany().HasForeignKey(c => c.OrderId).OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(c => c.OrderId);
        });

        model.Entity<Supply>(b =>
        {
            b.ToTable("supplies");
            Tracked(b);
            b.Property(s => s.Status).HasConversion<string>().HasMaxLength(16);
            b.Property(s => s.Notes).HasMaxLength(300);
            b.HasOne<Party>().WithMany().HasForeignKey(s => s.SupplierId).OnDelete(DeleteBehavior.Restrict);
            b.HasMany(s => s.Lines).WithOne().HasForeignKey(l => l.SupplyId).OnDelete(DeleteBehavior.Cascade);
            b.HasOne<PartyLocation>().WithMany().HasForeignKey(s => s.LoadingLocationId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(s => new { s.SupplierId, s.SupplyDate });
        });

        model.Entity<SupplyLine>(b =>
        {
            b.ToTable("supply_lines");
            Line(b, l => l.MaterialId, l => l.GradeId, l => l.UnitId, l => l.OriginCountryId);
            b.Property(l => l.Quantity).HasPrecision(18, 3);
            b.Property(l => l.QuantityKg).HasPrecision(18, 3);
        });
    }

    private static void Tracked<T>(EntityTypeBuilder<T> b) where T : TrackedEntity
    {
        b.Property(e => e.Id).ValueGeneratedNever();
        // xmin يتغير مع كل تعديل للسجل في PostgreSQL ويُستخدم لكشف التعديل المتزامن.
        b.Property(e => e.Version).HasColumnName("xmin").HasColumnType("xid").ValueGeneratedOnAddOrUpdate().IsConcurrencyToken();
        b.HasIndex(e => e.UpdatedAt);
    }

    private static void Line<T>(EntityTypeBuilder<T> b,
        System.Linq.Expressions.Expression<Func<T, object?>> material,
        System.Linq.Expressions.Expression<Func<T, object?>> grade,
        System.Linq.Expressions.Expression<Func<T, object?>> unit,
        System.Linq.Expressions.Expression<Func<T, object?>> origin) where T : class
    {
        b.HasOne<Material>().WithMany().HasForeignKey(material).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<Grade>().WithMany().HasForeignKey(grade).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<Unit>().WithMany().HasForeignKey(unit).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<LookupItem>().WithMany().HasForeignKey(origin).OnDelete(DeleteBehavior.Restrict);
    }
}
