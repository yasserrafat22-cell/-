using System.Globalization;
using System.Text;

namespace Qadisiyah.Domain.Common;

/// <summary>
/// تطبيع النصوص للبحث وكشف التكرار: توحيد أشكال الحروف العربية وإزالة التشكيل
/// والتطويل وتحويل الأرقام وحالة الحروف وتوحيد المسافات.
/// </summary>
public static class TextNormalizer
{
    public static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "";

        var builder = new StringBuilder(value.Length);
        foreach (var raw in value.Normalize(NormalizationForm.FormC))
        {
            var c = raw switch
            {
                'أ' or 'إ' or 'آ' or 'ٱ' => 'ا',
                'ة' => 'ه',
                'ى' => 'ي',
                'ؤ' => 'و',
                'ئ' => 'ي',
                'ـ' => '\0',
                >= '٠' and <= '٩' => (char)('0' + (raw - '٠')),
                >= '۰' and <= '۹' => (char)('0' + (raw - '۰')),
                _ => raw,
            };
            if (c == '\0' || CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark)
                continue;
            builder.Append(char.IsWhiteSpace(c) ? ' ' : char.ToLowerInvariant(c));
        }
        return string.Join(' ', builder.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>كود الخامة أو الـ Grade دون فواصل: «SG-5» و«sg 5» و«SG5» تصبح «sg5».</summary>
    public static string NormalizeCode(string? value) =>
        new(Normalize(value).Where(char.IsLetterOrDigit).ToArray());
}
