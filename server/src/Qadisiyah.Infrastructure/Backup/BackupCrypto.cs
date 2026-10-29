using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Qadisiyah.Infrastructure.Backup;

/// <summary>
/// تشفير النسخة الكاملة. المحتوى أجزاء AES-256-GCM مرقمة بمفتاح عشوائي، وآخر جزء معلّم
/// حتى يُكشف أي قص أو تبديل أو تعديل.
/// <list type="bullet">
/// <item>QBKW (من السيرفر للتطبيق): المفتاح مغلف بـ ECDH P-256 لمفتاح عام مؤقت يرسله التطبيق؛
/// لا تمر كلمة مرور ولا مفتاح فك على الشبكة.</item>
/// <item>QBK2 (الملف المحفوظ): التطبيق يعيد تغليف نفس المفتاح بكلمة مرور المدير
/// (PBKDF2-SHA256) على الجهاز فقط.</item>
/// <item>QBK1: الصيغة السابقة (المفتاح مشتق من كلمة المرور مباشرة)، مدعومة لفك النسخ القديمة.</item>
/// </list>
/// </summary>
public static class BackupCrypto
{
    private static readonly byte[] Magic1 = "QBK1"u8.ToArray();
    private static readonly byte[] Magic2 = "QBK2"u8.ToArray();
    private static readonly byte[] MagicWire = "QBKW"u8.ToArray();
    private static readonly byte[] WrapLabel = "QBK-WRAP-1"u8.ToArray();
    private const int Iterations = 600_000;
    private const int ChunkSize = 1024 * 1024;
    private const int TagSize = 16;
    public const int PublicKeySize = 65;
    public const int MinPasswordLength = 10;

    /// <summary>صيغة QBK1 (مستخدمة سابقًا والاختبارات؛ النسخ الجديدة تُنشأ بـ <see cref="EncryptForDeviceAsync"/>).</summary>
    public static async Task EncryptAsync(Stream input, Stream output, string password, CancellationToken ct)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var prefix = RandomNumberGenerator.GetBytes(4);
        var header = new byte[28];
        Magic1.CopyTo(header, 0);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), Iterations);
        salt.CopyTo(header, 8);
        prefix.CopyTo(header, 24);
        await output.WriteAsync(header, ct);
        await EncryptChunksAsync(input, output, DeriveKey(password, salt, Iterations), prefix, ct);
    }

    /// <summary>
    /// للتطبيق: مفتاح عشوائي للمحتوى، مغلف لمفتاح الجهاز العام المؤقت (65 بايت، نقطة P-256 غير مضغوطة).
    /// </summary>
    public static async Task EncryptForDeviceAsync(Stream input, Stream output, byte[] devicePublicKey,
        CancellationToken ct)
    {
        using var device = ImportPublicKey(devicePublicKey);
        using var server = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        var kek = WrapKey(server.DeriveRawSecretAgreement(device.PublicKey));
        var dataKey = RandomNumberGenerator.GetBytes(32);
        var nonce = RandomNumberGenerator.GetBytes(12);
        var wrapped = new byte[32];
        var tag = new byte[TagSize];
        using (var aes = new AesGcm(kek, TagSize))
            aes.Encrypt(nonce, dataKey, wrapped, tag, MagicWire);
        var prefix = RandomNumberGenerator.GetBytes(4);

        await output.WriteAsync(MagicWire, ct);
        await output.WriteAsync(ExportPublicKey(server), ct);
        await output.WriteAsync(nonce, ct);
        await output.WriteAsync(wrapped, ct);
        await output.WriteAsync(tag, ct);
        await output.WriteAsync(prefix, ct);
        await EncryptChunksAsync(input, output, dataKey, prefix, ct);
    }

    /// <summary>ما يفعله التطبيق على الجهاز: فك المفتاح بمفتاح الجهاز الخاص وإعادة تغليفه بكلمة المرور.</summary>
    public static async Task WireToPasswordFileAsync(Stream wire, Stream output, ECDiffieHellman device,
        string password, CancellationToken ct, int iterations = Iterations)
    {
        var header = new byte[4 + PublicKeySize + 12 + 32 + TagSize];
        if (await ReadFullAsync(wire, header, ct) != header.Length || !header.AsSpan(0, 4).SequenceEqual(MagicWire))
            throw new CryptographicException("استجابة النسخة غير صالحة");
        using var server = ImportPublicKey(header.AsSpan(4, PublicKeySize).ToArray());
        var kek = WrapKey(device.DeriveRawSecretAgreement(server.PublicKey));
        var dataKey = new byte[32];
        using (var aes = new AesGcm(kek, TagSize))
            aes.Decrypt(header.AsSpan(4 + PublicKeySize, 12), header.AsSpan(4 + PublicKeySize + 12, 32),
                header.AsSpan(4 + PublicKeySize + 44, TagSize), dataKey, MagicWire);

        var salt = RandomNumberGenerator.GetBytes(16);
        var nonce = RandomNumberGenerator.GetBytes(12);
        var wrapped = new byte[32];
        var tag = new byte[TagSize];
        using (var aes = new AesGcm(DeriveKey(password, salt, iterations), TagSize))
            aes.Encrypt(nonce, dataKey, wrapped, tag, Magic2);
        var head = new byte[8];
        Magic2.CopyTo(head, 0);
        BinaryPrimitives.WriteInt32BigEndian(head.AsSpan(4), iterations);
        await output.WriteAsync(head, ct);
        await output.WriteAsync(salt, ct);
        await output.WriteAsync(nonce, ct);
        await output.WriteAsync(wrapped, ct);
        await output.WriteAsync(tag, ct);
        await wire.CopyToAsync(output, ct);
    }

    /// <summary>يفك QBK2 أو QBK1؛ كلمة مرور خاطئة أو ملف معدل/ناقص يرفع <see cref="CryptographicException"/>.</summary>
    public static async Task DecryptAsync(Stream input, Stream output, string password, CancellationToken ct)
    {
        var magic = new byte[8];
        if (await ReadFullAsync(input, magic, ct) != 8)
            throw new CryptographicException("الملف ليس نسخة احتياطية من التطبيق");
        var iterations = BinaryPrimitives.ReadInt32BigEndian(magic.AsSpan(4));
        if (iterations is < 100_000 or > 10_000_000)
            throw new CryptographicException("ترويسة النسخة غير صالحة");

        if (magic.AsSpan(0, 4).SequenceEqual(Magic2))
        {
            var head = new byte[16 + 12 + 32 + TagSize + 4];
            if (await ReadFullAsync(input, head, ct) != head.Length)
                throw new CryptographicException("النسخة ناقصة");
            var dataKey = new byte[32];
            try
            {
                using var aes = new AesGcm(DeriveKey(password, head[..16], iterations), TagSize);
                aes.Decrypt(head.AsSpan(16, 12), head.AsSpan(28, 32), head.AsSpan(60, TagSize), dataKey, Magic2);
            }
            catch (AuthenticationTagMismatchException)
            {
                throw new CryptographicException("كلمة مرور النسخة غير صحيحة");
            }
            await DecryptChunksAsync(input, output, dataKey, head[^4..], ct);
            return;
        }
        if (magic.AsSpan(0, 4).SequenceEqual(Magic1))
        {
            var rest = new byte[20];
            if (await ReadFullAsync(input, rest, ct) != rest.Length)
                throw new CryptographicException("النسخة ناقصة");
            await DecryptChunksAsync(input, output, DeriveKey(password, rest[..16], iterations), rest[16..], ct,
                firstChunkMeansPassword: true);
            return;
        }
        throw new CryptographicException("الملف ليس نسخة احتياطية من التطبيق");
    }

    private static async Task EncryptChunksAsync(Stream input, Stream output, byte[] key, byte[] prefix,
        CancellationToken ct)
    {
        using var aes = new AesGcm(key, TagSize);
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

    private static async Task DecryptChunksAsync(Stream input, Stream output, byte[] key, byte[] prefix,
        CancellationToken ct, bool firstChunkMeansPassword = false)
    {
        using var aes = new AesGcm(key, TagSize);
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
                throw new CryptographicException(counter == 0 && firstChunkMeansPassword
                    ? "كلمة مرور النسخة غير صحيحة"
                    : "النسخة معدلة أو تالفة");
            }
            await output.WriteAsync(plain, ct);
            if (final)
                return;
            counter++;
        }
    }

    public static ECDiffieHellman ImportPublicKey(byte[] point)
    {
        if (point.Length != PublicKeySize || point[0] != 0x04)
            throw new CryptographicException("المفتاح العام غير صالح");
        var key = ECDiffieHellman.Create();
        key.ImportParameters(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = point[1..33], Y = point[33..] },
        });
        return key;
    }

    public static byte[] ExportPublicKey(ECDiffieHellman key)
    {
        var q = key.ExportParameters(false).Q;
        return [0x04, .. q.X!, .. q.Y!];
    }

    private static byte[] WrapKey(byte[] shared) => SHA256.HashData([.. shared, .. WrapLabel]);

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
