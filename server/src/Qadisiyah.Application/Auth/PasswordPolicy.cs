using System.Security.Cryptography;

namespace Qadisiyah.Application.Auth;

public static class PasswordPolicy
{
    public const int MinLength = 8;

    /// <summary>يعيد سبب الرفض بالعربية، أو null إذا كانت كلمة المرور مقبولة.</summary>
    public static string? Validate(string password)
    {
        if (password.Length < MinLength)
            return $"كلمة المرور يجب ألا تقل عن {MinLength} أحرف";
        if (!password.Any(char.IsLetter) || !password.Any(char.IsDigit))
            return "كلمة المرور يجب أن تحتوي على حروف وأرقام";
        return null;
    }

    private const string TemporaryAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";

    /// <summary>كلمة مرور مؤقتة عشوائية تحقق السياسة، دون حروف متشابهة (0/O، 1/l).</summary>
    public static string GenerateTemporary(int length = 12)
    {
        while (true)
        {
            var candidate = RandomNumberGenerator.GetString(TemporaryAlphabet, length);
            if (Validate(candidate) is null)
                return candidate;
        }
    }
}
