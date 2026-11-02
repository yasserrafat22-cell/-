using System.Globalization;
using System.IO.Compression;
using System.Xml;
using System.Xml.Linq;

namespace Qadisiyah.Application.Common;

/// <summary>قراءة أوراق ملف Excel (xlsx) كنصوص، دون مكتبات خارجية.</summary>
public static class XlsxReader
{
    private static readonly XNamespace Main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    private static readonly XNamespace Rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    private static readonly XNamespace PackageRel = "http://schemas.openxmlformats.org/package/2006/relationships";
    public const int MaxRows = 20_000;

    /// <summary>الصفوف كنصوص (الخلايا الفارغة نص فارغ). يرمي <see cref="InvalidDataException"/> لملف غير صالح.</summary>
    public static List<string[]> Read(Stream content) => ReadSheets(content, firstOnly: true)[0].Rows;

    /// <summary>
    /// كل أوراق الملف بأسمائها وترتيبها (الصفوف كنصوص). <paramref name="firstOnly"/> يقرأ الأولى فقط.
    /// يرمي <see cref="InvalidDataException"/> لملف غير صالح.
    /// </summary>
    public static List<(string Name, List<string[]> Rows)> ReadSheets(Stream content, bool firstOnly = false) =>
        ReadNumberedSheets(content, firstOnly).Select(s => (s.Name, s.Rows.Select(r => r.Cells).ToList())).ToList();

    /// <summary>
    /// مثل <see cref="ReadSheets"/> مع رقم كل صف في الملف كما يعرضه Excel (يبدأ من 1)، حتى بعد تجاوز
    /// الصفوف الفارغة.
    /// </summary>
    public static List<(string Name, List<(int Row, string[] Cells)> Rows)> ReadNumberedSheets(Stream content,
        bool firstOnly = false)
    {
        try
        {
            using var zip = new ZipArchive(content, ZipArchiveMode.Read, leaveOpen: true);
            var shared = new List<string>();
            if (zip.GetEntry("xl/sharedStrings.xml") is { } sst)
                shared = Load(sst).Root!.Elements(Main + "si").Select(Text).ToList();

            var sheets = new List<(string Name, string Path)>();
            if (zip.GetEntry("xl/workbook.xml") is { } wb && zip.GetEntry("xl/_rels/workbook.xml.rels") is { } rels)
            {
                var targets = Load(rels).Root!.Elements(PackageRel + "Relationship")
                    .ToDictionary(r => r.Attribute("Id")?.Value ?? "", r => r.Attribute("Target")?.Value);
                foreach (var sheetElement in Load(wb).Root!.Element(Main + "sheets")?.Elements(Main + "sheet") ?? [])
                {
                    var target = targets.GetValueOrDefault(sheetElement.Attribute(Rel + "id")?.Value ?? "");
                    if (target is null)
                        continue;
                    sheets.Add((sheetElement.Attribute("name")?.Value ?? $"Sheet{sheets.Count + 1}",
                        target.StartsWith('/') ? target.TrimStart('/') : "xl/" + target));
                    if (firstOnly)
                        break;
                }
            }
            if (sheets.Count == 0)
                sheets.Add(("Sheet1", "xl/worksheets/sheet1.xml"));

            var result = new List<(string Name, List<(int Row, string[] Cells)> Rows)>();
            foreach (var (name, path) in sheets)
            {
                var sheet = zip.GetEntry(path) ?? throw new InvalidDataException("لا توجد ورقة بيانات في الملف");
                result.Add((name, ReadRows(sheet, shared)));
            }
            return result;
        }
        catch (Exception e) when (e is InvalidDataException or XmlException or IOException)
        {
            throw new InvalidDataException(e is InvalidDataException ide && ide.Message.Length < 120 && ide.Message.Any(ch => ch > 127)
                ? ide.Message
                : "الملف ليس ملف Excel صالحًا (xlsx)", e);
        }
    }

    private static List<(int Row, string[] Cells)> ReadRows(ZipArchiveEntry sheet, List<string> shared)
    {
        var rows = new List<(int Row, string[] Cells)>();
        var number = 0;
        foreach (var row in Load(sheet).Root!.Element(Main + "sheetData")?.Elements(Main + "row") ?? [])
        {
            number = int.TryParse(row.Attribute("r")?.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var rowNumber)
                ? rowNumber
                : number + 1;
            if (rows.Count >= MaxRows)
                throw new InvalidDataException($"الحد الأقصى {MaxRows} صف في الملف الواحد");
            var cells = new SortedDictionary<int, string>();
            var next = 0;
            foreach (var c in row.Elements(Main + "c"))
            {
                var index = c.Attribute("r")?.Value is { } r ? ColumnIndex(r) : next;
                next = index + 1;
                var type = c.Attribute("t")?.Value;
                var raw = c.Element(Main + "v")?.Value;
                cells[index] = (type switch
                {
                    "s" when int.TryParse(raw, CultureInfo.InvariantCulture, out var i) && i < shared.Count => shared[i],
                    "inlineStr" => Text(c.Element(Main + "is")!),
                    "b" => raw == "1" ? "TRUE" : "FALSE",
                    _ => Number(raw),
                }).Trim();
            }
            if (cells.Count == 0)
                continue;
            var values = new string[cells.Keys.Max() + 1];
            Array.Fill(values, "");
            foreach (var (i, v) in cells)
                values[i] = v;
            rows.Add((number, values));
        }
        return rows;
    }

    private static XDocument Load(ZipArchiveEntry entry)
    {
        using var stream = entry.Open();
        return XDocument.Load(stream, LoadOptions.None);
    }

    private static string Text(XElement item) => string.Concat(item.Descendants(Main + "t").Select(t => t.Value));

    /// <summary>الأرقام الطويلة (مثل الهواتف) كما هي دون صيغة علمية أو كسور.</summary>
    private static string Number(string? raw) =>
        raw is not null && double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var d)
            && Math.Abs(d % 1) < 1e-9 && Math.Abs(d) < 1e15
            ? ((long)d).ToString(CultureInfo.InvariantCulture)
            : raw ?? "";

    private static int ColumnIndex(string reference)
    {
        var index = 0;
        foreach (var ch in reference.TakeWhile(char.IsLetter))
            index = index * 26 + (char.ToUpperInvariant(ch) - 'A' + 1);
        return index - 1;
    }
}
