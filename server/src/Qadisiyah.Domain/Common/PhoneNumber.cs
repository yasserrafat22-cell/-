using System.Text.RegularExpressions;

namespace Qadisiyah.Domain.Common;

/// <summary>
/// توحيد أرقام الهاتف بصيغة E.164 (مثل +201001234567) لكشف التكرار وروابط
/// الاتصال وواتساب. الافتراضي مصر، مع دعم الأرقام الدولية بعلامة + أو 00.
/// </summary>
public static partial class PhoneNumber
{
    [GeneratedRegex(@"^\+[1-9]\d{7,14}$")]
    private static partial Regex E164();

    public static string? Normalize(string? input, string defaultCountryCode = "20")
    {
        if (string.IsNullOrWhiteSpace(input))
            return null;

        var digits = TextNormalizer.Normalize(input);
        var plus = digits.StartsWith('+');
        digits = new string(digits.Where(char.IsAsciiDigit).ToArray());

        string candidate;
        if (plus)
            candidate = "+" + digits;
        else if (digits.StartsWith("00", StringComparison.Ordinal))
            candidate = "+" + digits[2..];
        else if (digits.StartsWith('0'))
            candidate = "+" + defaultCountryCode + digits[1..];
        else if (digits.StartsWith(defaultCountryCode, StringComparison.Ordinal) && digits.Length >= 11)
            candidate = "+" + digits;
        else
            candidate = "+" + defaultCountryCode + digits;

        return E164().IsMatch(candidate) ? candidate : null;
    }
}
