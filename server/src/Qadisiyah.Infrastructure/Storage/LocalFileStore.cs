using System.Text.RegularExpressions;
using Qadisiyah.Application.Common;

namespace Qadisiyah.Infrastructure.Storage;

public sealed class AttachmentOptions
{
    public const string Section = "Attachments";

    /// <summary>
    /// مجلد التخزين الدائم. في Docker هو volume مستقل (/data/attachments)
    /// يبقى مع التحديثات ويدخل في النسخ الاحتياطي.
    /// </summary>
    public string Root { get; set; } = "";
}

/// <summary>تخزين المرفقات على القرص في مجلد واحد مقسم حسب الشهر.</summary>
public sealed partial class LocalFileStore(AttachmentOptions options) : IFileStore
{
    [GeneratedRegex(@"^[0-9]{4}/[0-9]{2}/[0-9a-f]{32}$")]
    private static partial Regex ValidKey();

    private string PathOf(string key)
    {
        if (!ValidKey().IsMatch(key))
            throw new ArgumentException("Invalid storage key", nameof(key));
        return Path.Combine(options.Root, key.Replace('/', Path.DirectorySeparatorChar));
    }

    public async Task SaveAsync(string key, Stream content, CancellationToken ct)
    {
        var path = PathOf(key);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".part";
        await using (var file = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
        {
            await content.CopyToAsync(file, ct);
            await file.FlushAsync(ct);
        }
        File.Move(temp, path, overwrite: false);
    }

    public Stream? OpenRead(string key)
    {
        var path = PathOf(key);
        return File.Exists(path)
            ? new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true)
            : null;
    }
}
