using Microsoft.EntityFrameworkCore;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Infrastructure.Persistence;

/// <summary>
/// القوائم المرجعية الابتدائية (قوائم عامة في المجال، وليست بيانات تجارية).
/// تُضاف العناصر الناقصة فقط حسب الكود؛ أي تعديل أجراه المدير على عنصر موجود
/// لا يُستبدل عند التحديث، ولا يُعاد إنشاء عنصر عطّله المدير.
/// </summary>
internal static class ReferenceSeed
{
    private sealed record Lookup(string Category, string Code, string NameAr, string? Semantic = null,
        string AppliesTo = LookupAppliesTo.Both, string? NameEn = null);

    private static readonly Lookup[] Lookups =
    [
        // أنواع النشاط (ص7، ص8، ص9).
        new(LookupCategories.ActivityType, "factory", "مصنع", AppliesTo: LookupAppliesTo.Both),
        new(LookupCategories.ActivityType, "converter", "محول بلاستيك", AppliesTo: LookupAppliesTo.Customer),
        new(LookupCategories.ActivityType, "trader", "تاجر", AppliesTo: LookupAppliesTo.Both),
        new(LookupCategories.ActivityType, "distributor", "موزع", AppliesTo: LookupAppliesTo.Both),
        new(LookupCategories.ActivityType, "importer", "مستورد", AppliesTo: LookupAppliesTo.Supplier),
        new(LookupCategories.ActivityType, "other", "أخرى", AppliesTo: LookupAppliesTo.Both),

        // نتائج التواصل: للعملاء كما في ص8، وللموردين كما في ص9 (قرار T3).
        new(LookupCategories.ContactOutcome, "reached", "تم التواصل بنجاح", ContactOutcomeSemantics.Reached),
        new(LookupCategories.ContactOutcome, "no_answer", "لم يتم الرد", ContactOutcomeSemantics.NoAnswer),
        new(LookupCategories.ContactOutcome, "pending", "في انتظار الرد", ContactOutcomeSemantics.Pending),
        new(LookupCategories.ContactOutcome, "price_requested", "طلب عرض سعر", ContactOutcomeSemantics.PriceRequested,
            LookupAppliesTo.Customer),
        new(LookupCategories.ContactOutcome, "follow_up_agreed", "تم الاتفاق على المتابعة",
            ContactOutcomeSemantics.FollowUpAgreed, LookupAppliesTo.Supplier),
        new(LookupCategories.ContactOutcome, "price_sent", "أرسل عرض سعر", ContactOutcomeSemantics.PriceRequested,
            LookupAppliesTo.Supplier),
        new(LookupCategories.ContactOutcome, "other", "أخرى", ContactOutcomeSemantics.Other),

        new(LookupCategories.Currency, "EGP", "جنيه مصري", NameEn: "EGP"),
        new(LookupCategories.Currency, "USD", "دولار أمريكي", NameEn: "USD"),
        new(LookupCategories.Currency, "EUR", "يورو", NameEn: "EUR"),

        .. new[]
        {
            "القاهرة", "الجيزة", "الإسكندرية", "القليوبية", "الشرقية", "الدقهلية", "الغربية", "المنوفية",
            "البحيرة", "كفر الشيخ", "دمياط", "بورسعيد", "الإسماعيلية", "السويس", "الفيوم", "بني سويف",
            "المنيا", "أسيوط", "سوهاج", "قنا", "الأقصر", "أسوان", "البحر الأحمر", "الوادي الجديد",
            "مطروح", "شمال سيناء", "جنوب سيناء",
        }.Select((name, i) => new Lookup(LookupCategories.Governorate, $"eg-{i + 1:00}", name)),

        // بلدان الصنع الشائعة للخامات (ISO 3166). المدير يضيف غيرها من الكتالوج.
        .. new[]
        {
            ("SA", "السعودية"), ("EG", "مصر"), ("AE", "الإمارات"), ("QA", "قطر"), ("KW", "الكويت"),
            ("OM", "عُمان"), ("BH", "البحرين"), ("IR", "إيران"), ("TR", "تركيا"), ("IN", "الهند"),
            ("CN", "الصين"), ("KR", "كوريا الجنوبية"), ("TW", "تايوان"), ("JP", "اليابان"),
            ("SG", "سنغافورة"), ("TH", "تايلاند"), ("MY", "ماليزيا"), ("RU", "روسيا"),
            ("US", "الولايات المتحدة"), ("BE", "بلجيكا"), ("NL", "هولندا"), ("DE", "ألمانيا"),
            ("FR", "فرنسا"), ("IT", "إيطاليا"), ("ES", "إسبانيا"), ("BR", "البرازيل"), ("DZ", "الجزائر"),
        }.Select(c => new Lookup(LookupCategories.Country, c.Item1, c.Item2)),
    ];

    private static readonly (string Code, string NameAr, decimal Factor)[] Units =
    [
        ("kg", "كجم", 1m),
        ("ton", "طن", 1000m),
        ("bag25", "شيكارة 25 كجم", 25m),
    ];

    private static readonly (string Code, string NameAr, string NameEn, string[] Aliases)[] Materials =
    [
        ("PVC", "بولي فينيل كلوريد", "Polyvinyl chloride", ["بي في سي", "بولي فينيل كلورايد"]),
        ("PP", "بولي بروبيلين", "Polypropylene", ["بي بي", "بولي بروبلين"]),
        ("HDPE", "بولي إيثيلين عالي الكثافة", "High-density polyethylene", ["اتش دي", "هاي دنسيتي"]),
        ("LDPE", "بولي إيثيلين منخفض الكثافة", "Low-density polyethylene", ["ال دي", "لو دنسيتي"]),
        ("LLDPE", "بولي إيثيلين منخفض الكثافة الخطي", "Linear low-density polyethylene", ["لينير"]),
        ("PET", "بولي إيثيلين تيرفثالات", "Polyethylene terephthalate", ["بت", "بي اي تي"]),
        ("PS", "بولي ستايرين", "Polystyrene", ["بولي ستيرين"]),
        ("ABS", "أكريلونيتريل بيوتادين ستايرين", "Acrylonitrile butadiene styrene", []),
        ("PC", "بولي كربونات", "Polycarbonate", []),
        ("PA", "بولي أميد (نايلون)", "Polyamide", ["نايلون"]),
    ];

    public static async Task SeedAsync(AppDbContext db, CancellationToken ct)
    {
        var existingLookups = await db.LookupItems.Select(l => new { l.Category, l.Code }).ToListAsync(ct);
        var order = 0;
        foreach (var l in Lookups)
        {
            order++;
            if (existingLookups.Any(e => e.Category == l.Category && e.Code == l.Code))
                continue;
            db.LookupItems.Add(new LookupItem
            {
                Category = l.Category,
                Code = l.Code,
                NameAr = l.NameAr,
                NameEn = l.NameEn,
                Semantic = l.Semantic,
                AppliesTo = l.AppliesTo,
                SortOrder = order,
                IsSystem = true,
            });
        }

        var existingUnits = await db.Units.Select(u => u.Code).ToListAsync(ct);
        foreach (var (code, name, factor) in Units.Where(u => !existingUnits.Contains(u.Code)))
            db.Units.Add(new Unit { Code = code, NameAr = name, FactorToKg = factor, SortOrder = Array.FindIndex(Units, u => u.Code == code) });

        var existingMaterials = await db.Materials.Select(m => m.Code).ToListAsync(ct);
        foreach (var (code, nameAr, nameEn, aliases) in Materials.Where(m => !existingMaterials.Contains(m.Code)))
        {
            var material = new Material
            {
                Code = code,
                NameAr = nameAr,
                NameEn = nameEn,
                SortOrder = Array.FindIndex(Materials, m => m.Code == code),
            };
            foreach (var alias in aliases.Prepend(code).Append(nameAr).Append(nameEn))
                material.Aliases.Add(new MaterialAlias { Alias = alias, Normalized = TextNormalizer.Normalize(alias) });
            db.Materials.Add(material);
        }

        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// قائمة الخامات والشركات المعتمدة من المالك لشاشة تسجيل العميل. تُضاف الناقصة فقط
    /// (مطابقة بالكود أو الاسم المعروف) ولا يُعدّل أي موجود. PR200 و Borouge 150 تسميات
    /// تجارية كما كتبها المالك: تُحفظ بنصها دون نسبها لعائلة بوليمر.
    /// </summary>
    private static readonly (string Code, string NameAr, string? NameEn)[] OwnerMaterials =
    [
        ("GPPS", "بولي ستايرين عام الاستخدام", "General purpose polystyrene"),
        ("HIPS", "بولي ستايرين عالي الصدمات", "High impact polystyrene"),
        ("SAN", "ستايرين أكريلونيتريل", "Styrene acrylonitrile"),
        ("PA6", "نايلون 6", "Polyamide 6"),
        ("PA66", "نايلون 66", "Polyamide 66"),
        ("POM", "بولي أسيتال", "Polyoxymethylene"),
        ("PBT", "بولي بيوتيلين تيرفثالات", "Polybutylene terephthalate"),
        ("ASA", "أكريلونيتريل ستايرين أكريلات", "Acrylonitrile styrene acrylate"),
        ("EVA", "إيثيلين فينيل أسيتات", "Ethylene vinyl acetate"),
        ("PR200", "PR200", null),
        ("Borouge 150", "Borouge 150", null),
    ];

    public static readonly string[] OwnerManufacturers =
        ["SABIC", "Marlex", "Advanced", "Tasnee", "Kayan", "Petro", "Sadara", "Borouge", "Chem", "OQ"];

    public static async Task EnsureOwnerCatalogAsync(AppDbContext db, CancellationToken ct)
    {
        var aliases = await db.MaterialAliases.Select(a => a.Normalized).ToListAsync(ct);
        var codes = (await db.Materials.Select(m => m.Code).ToListAsync(ct)).Select(TextNormalizer.NormalizeCode).ToHashSet();
        var known = aliases.Select(a => new string(a.Where(char.IsLetterOrDigit).ToArray())).Concat(codes).ToHashSet();
        foreach (var (code, nameAr, nameEn) in OwnerMaterials)
        {
            var key = TextNormalizer.NormalizeCode(code);
            if (known.Contains(key))
                continue;
            var material = new Material { Code = code, NameAr = nameAr, NameEn = nameEn, SortOrder = 500 };
            material.Aliases.Add(new MaterialAlias { Alias = code, Normalized = key });
            db.Materials.Add(material);
            known.Add(key);
        }

        var makers = await db.Manufacturers.Select(m => m.NormalizedName).ToListAsync(ct);
        foreach (var name in OwnerManufacturers)
        {
            var normalized = TextNormalizer.Normalize(name);
            if (Synonyms.MakerVariants(normalized).Any(makers.Contains))
                continue;
            db.Manufacturers.Add(new Manufacturer { Name = name, NormalizedName = normalized });
            makers.Add(normalized);
        }
        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// كل مستخدم له ملف مندوب مرتبط بحسابه (يُختار تلقائيًا «المندوب المسؤول»
    /// عند التسجيل). يُنشأ الناقص فقط ولا يُعدّل الموجود.
    /// </summary>
    public static async Task EnsureRepresentativesAsync(AppDbContext db, CancellationToken ct)
    {
        var missing = await db.Users
            .Where(u => !db.Representatives.Any(r => r.UserId == u.Id))
            .Select(u => new { u.Id, u.DisplayName })
            .ToListAsync(ct);
        foreach (var user in missing)
            db.Representatives.Add(new Representative { Name = user.DisplayName, UserId = user.Id });
        await db.SaveChangesAsync(ct);
    }
}
