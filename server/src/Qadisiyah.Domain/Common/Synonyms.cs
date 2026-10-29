namespace Qadisiyah.Domain.Common;

/// <summary>
/// أسماء عربية/إنجليزية شائعة للشركات المصنّعة وأنواع الخامات، حتى يجد البحث «سابك» و«SABIC»
/// معًا دون خلط منتجات مختلفة (كل اسم يقود لرمز واحد فقط).
/// </summary>
public static class Synonyms
{
    private static readonly Dictionary<string, string> MakerTerms = Build(new Dictionary<string, string[]>
    {
        ["sabic"] = ["سابك", "sabic"],
        ["borouge"] = ["بروج", "borouge"],
        ["sipchem"] = ["سبكيم", "sipchem"],
        ["tasnee"] = ["التصنيع", "تصنيع", "tasnee"],
        ["exxonmobil"] = ["اكسون", "اكسون موبيل", "exxon", "exxonmobil", "exxon mobil"],
        ["lyondellbasell"] = ["ليونديل", "ليونديل باسل", "lyondell", "lyondellbasell", "basell"],
        ["dow"] = ["داو", "dow"],
        ["lg chem"] = ["ال جي", "ال جي كيم", "lg", "lg chem"],
        ["totalenergies"] = ["توتال", "total", "totalenergies"],
        ["sinopec"] = ["سينوبك", "ساينوبك", "sinopec"],
        ["formosa"] = ["فورموزا", "formosa"],
        ["braskem"] = ["براسكم", "braskem"],
        ["reliance"] = ["ريلاينس", "reliance"],
        ["ineos"] = ["اينيوس", "ineos"],
        ["lotte"] = ["لوتي", "lotte"],
        ["chevron phillips"] = ["شيفرون", "chevron", "chevron phillips"],
    });

    private static readonly Dictionary<string, string> MaterialTerms = Build(new Dictionary<string, string[]>
    {
        ["PP"] = ["pp", "بولي بروبلين", "بولي بروبيلين", "بروبلين", "polypropylene"],
        ["HDPE"] = ["hdpe", "بولي ايثيلين عالي الكثافه", "high density polyethylene"],
        ["LDPE"] = ["ldpe", "بولي ايثيلين منخفض الكثافه", "low density polyethylene"],
        ["LLDPE"] = ["lldpe", "linear low density polyethylene"],
        ["PVC"] = ["pvc", "بي في سي", "بولي فينيل كلورايد", "polyvinyl chloride"],
        ["ABS"] = ["abs", "ايه بي اس"],
        ["PA"] = ["pa", "polyamide", "بولي اميد", "نايلون", "nylon"],
        ["PS"] = ["ps", "بولي ستيرين", "polystyrene"],
        ["PC"] = ["pc", "بولي كربونات", "polycarbonate"],
        ["PET"] = ["pet", "بولي ايثيلين تيريفثالات"],
    });

    private static Dictionary<string, string> Build(Dictionary<string, string[]> groups) =>
        groups.SelectMany(g => g.Value.Select(v => (Key: TextNormalizer.Normalize(v), g.Key)))
            .ToDictionary(x => x.Key, x => x.Item2);

    /// <summary>كل الأسماء المكافئة لاسم شركة (للبحث في الأسماء المسجلة)، أو الاسم نفسه.</summary>
    public static IReadOnlyList<string> MakerVariants(string normalized)
    {
        if (!MakerTerms.TryGetValue(normalized, out var canonical))
            return [normalized];
        return [.. MakerTerms.Where(t => t.Value == canonical).Select(t => t.Key)];
    }

    /// <summary>رمز الخامة (PP، HDPE...) لاسم معروف، أو null.</summary>
    public static string? MaterialCode(string normalized) => MaterialTerms.GetValueOrDefault(normalized);
}
