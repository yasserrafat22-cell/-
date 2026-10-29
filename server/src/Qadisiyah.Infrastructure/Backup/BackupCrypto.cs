using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Qadisiyah.Infrastructure.Backup;

/// <summary>
/// تشفير ملف النسخة الكاملة بكلمة مرور يدخلها المدير لكل نسخة (لا تُحفظ في أي مكان).
/// المفتاح: PBKDF2-SHA256 بملح عشوائي. المحتوى: أجزاء AES-256-GCM مرقمة؛ آخر جزء
/// معلّم حتى يُكشف أي قص أو تبديل أو تعديل في الملف.
/// </summary>
public static class BackupCrypto
{
    private static readonly byte[] Magic = "QBK1"u8.ToArray();
    private const int Iterations = 600_000;
    private const int ChunkSize = 1024 * 1024;
    private const int TagSize = 16;
    public const int MinPasswordLength = 10;

    public static async Task EncryptAsync(Stream input, Stream output, string password, CancellationToken ct)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var prefix = RandomNumberGenerator.GetBytes(4);
        var header = new byte[4 + 4 + 16 + 4];
        Magic.CopyTo(header, 0);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), Iterations);
        salt.CopyTo(header, 8);
        prefix.CopyTo(header, 24);
        await output.WriteAsync(header, ct);

        using var aes = new AesGcm(DeriveKey(password, salt, Iterations), TagSize);
        var current = new byte[ChunkSize];
        var next = new byte[ChunkSize];
        var currentLength = await ReadFullAsync(input, current, ct);
        long counter = 0;
        while (true)
        {
            var nextLength = currentLength == ChunkSize ? await ReadFullAsync(input, next, ct) : 0;
            var final = nextLength == 0;
            var cipher = new byte[currentLength];
            var tag = new byte[TagSize];
            aes.Encrypt(Nonce(prefix, counter), current.AsSpan(0, currentLength), cipher, tag, new[] { final ? (byte)1 : (byte)0 });
            var length = new byte[4];
            BinaryPrimitives.WriteUInt32BigEndian(length, (uint)currentLength | (final ? 0x8000_0000u : 0));
            await output.WriteAsync(length, ct);
            await output.WriteAsync(cipher, ct);
            await output.WriteAsync(tag, ct);
            if (final)
                return;
            (current, next) = (next, current);
            currentLength = nextLength;
            counter++;
        }
    }

    /// <summary>يفك التشفير؛ كلمة مرور خاطئة أو ملف معدل/ناقص يرفع <see cref="CryptographicException"/>.</summary>
    public static async Task DecryptAsync(Stream input, Stream output, string password, CancellationToken ct)
    {
        var header = new byte[28];
        if (await ReadFullAsync(input, header, ct) != header.Length || !header.AsSpan(0, 4).SequenceEqual(Magic))
            throw new CryptographicException("الملف ليس نسخة احتياطية من التطبيق");
        var iterations = BinaryPrimitives.ReadInt32BigEndian(header.AsSpan(4));
        if (iterations is < 100_000 or > 10_000_000)
            throw new CryptographicException("ترويسة النسخة غير صالحة");
        var prefix = header.AsSpan(24, 4).ToArray();
        using var aes = new AesGcm(DeriveKey(password, header.AsSpan(8, 16).ToArray(), iterations), TagSize);

        var lengthBytes = new byte[4];
        long counter = 0;
        while (true)
        {
            if (await ReadFullAsync(input, lengthBytes, ct) != 4)
                throw new CryptographicException("النسخة ناقصة");
            var raw = BinaryPrimitives.ReadUInt32BigEndian(lengthBytes);
            var final = (raw & 0x8000_0000u) != 0;
            var length = (int)(raw & 0x7FFF_FFFFu);
            if (length > ChunkSize)
                throw new CryptographicException("جزء غير صالح في النسخة");
            var cipher = new byte[length];
            var tag = new byte[TagSize];
            if (await ReadFullAsync(input, cipher, ct) != length || await ReadFullAsync(input, tag, ct) != TagSize)
                throw new CryptographicException("النسخة ناقصة");
            var plain = new byte[length];
            try
            {
                aes.Decrypt(Nonce(prefix, counter), cipher, tag, plain, new[] { final ? (byte)1 : (byte)0 });
            }
            catch (AuthenticationTagMismatchException)
            {
                throw new CryptographicException(counter == 0
                    ? "كلمة مرور النسخة غير صحيحة"
                    : "النسخة معدلة أو تالفة");
            }
            await output.WriteAsync(plain, ct);
            if (final)
                return;
            counter++;
        }
    }

    private static byte[] DeriveKey(string password, byte[] salt, int iterations) =>
        Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password), salt, iterations, HashAlgorithmName.SHA256, 32);

    private static byte[] Nonce(byte[] prefix, long counter)
    {
        var nonce = new byte[12];
        prefix.CopyTo(nonce, 0);
        BinaryPrimitives.WriteInt64BigEndian(nonce.AsSpan(4), counter);
        return nonce;
    }

    private static async Task<int> ReadFullAsync(Stream input, byte[] buffer, CancellationToken ct)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var read = await input.ReadAsync(buffer.AsMemory(total), ct);
            if (read == 0)
                break;
            total += read;
        }
        return total;
    }
}
