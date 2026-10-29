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

    /// <summary>موبايل مصري: 010 أو 011 أو 012 أو 015 ثم 8 أرقام (11 رقمًا محليًا).</summary>
    [GeneratedRegex(@"^\+201[0125]\d{8}$")]
    private static partial Regex EgyptianMobile();

    /// <summary>أرضي مصري: كود المحافظة ثم الرقم (02 + 8 أرقام، أو كود من رقمين + 7 أرقام).</summary>
    [GeneratedRegex(@"^\+20[2-9]\d{7,8}$")]
    private static partial Regex EgyptianLandline();

    public static bool IsEgyptianMobile(string? e164) => e164 is not null && EgyptianMobile().IsMatch(e164);

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

        // الأرقام المصرية تُتحقق بقواعدها (موبايل أو أرضي)؛ الدولية بصيغة E.164 فقط.
        if (candidate.StartsWith("+20", StringComparison.Ordinal))
            return EgyptianMobile().IsMatch(candidate) || EgyptianLandline().IsMatch(candidate) ? candidate : null;
        return E164().IsMatch(candidate) ? candidate : null;
    }
}
