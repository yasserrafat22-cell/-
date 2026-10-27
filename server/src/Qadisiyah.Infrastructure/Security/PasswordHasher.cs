using Microsoft.AspNetCore.Identity;
using Qadisiyah.Application;

namespace Qadisiyah.Infrastructure.Security;

/// <summary>
/// يعتمد على خوارزمية ASP.NET Core Identity (PBKDF2-HMAC-SHA512 مع salt
/// عشوائي وعدد تكرارات مرتفع) بدل كتابة خوارزمية تشفير خاصة.
/// </summary>
public sealed class PasswordHasher : IPasswordHasher
{
    private static readonly object Subject = new();
    private readonly PasswordHasher<object> inner = new();

    public string Hash(string password) => inner.HashPassword(Subject, password);

    public bool Verify(string hash, string password) =>
        inner.VerifyHashedPassword(Subject, hash, password) is not PasswordVerificationResult.Failed;
}
