using System.IO.Compression;
using System.Security;
using System.Text;

namespace Qadisiyah.Application.Common;

/// <summary>ملف Excel (xlsx) بسيط بورقة واحدة من اليمين لليسار، دون مكتبات خارجية.</summary>
public sealed record XlsxSheet(string Name, IReadOnlyList<string> Headers, IEnumerable<IReadOnlyList<object?>> Rows,
    IReadOnlyList<int>? Widths = null);

public static class XlsxWriter
{
    public static byte[] Write(string sheetName, IReadOnlyList<string> headers, IEnumerable<IReadOnlyList<object?>> rows) =>
        WriteSheets([new XlsxSheet(sheetName, headers, rows)]);

    /// <summary>ملف بعدة أوراق (مثل «العملاء» و«الموردون»)، لكل ورقة عناوينها وعرض أعمدتها.</summary>
    public static byte[] WriteSheets(IReadOnlyList<XlsxSheet> sheets)
    {
        using var buffer = new MemoryStream();
        using (var zip = new ZipArchive(buffer, ZipArchiveMode.Create, leaveOpen: true))
        {
            var overrides = string.Concat(sheets.Select((_, i) =>
                $"<Override PartName=\"/xl/worksheets/sheet{i + 1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"));
            Add(zip, "[Content_Types].xml", $"""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
                <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
                <Default Extension="xml" ContentType="application/xml"/>
                <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
                {overrides}
                <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
                </Types>
                """);
            Add(zip, "_rels/.rels", """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
                </Relationships>
                """);
            var sheetList = string.Concat(sheets.Select((sh, i) =>
                $"<sheet name=\"{SecurityElement.Escape(SheetName(sh.Name))}\" sheetId=\"{i + 1}\" r:id=\"rId{i + 1}\"/>"));
            Add(zip, "xl/workbook.xml", $"""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                <sheets>{sheetList}</sheets>
                </workbook>
                """);
            var sheetRels = string.Concat(sheets.Select((_, i) =>
                $"<Relationship Id=\"rId{i + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet{i + 1}.xml\"/>"));
            Add(zip, "xl/_rels/workbook.xml.rels", $"""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                {sheetRels}
                <Relationship Id="rId{sheets.Count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
                </Relationships>
                """);
            // نمط 1: عنوان عريض؛ نمط 2: تاريخ.
            Add(zip, "xl/styles.xml", """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts>
                <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
                <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
                <borders count="1"><border/></borders>
                <cellStyleXfs count="1"><xf/></cellStyleXfs>
                <cellXfs count="3"><xf/><xf fontId="1" applyFont="1"/><xf numFmtId="164" applyNumberFormat="1"/></cellXfs>
                </styleSheet>
                """);

            for (var i = 0; i < sheets.Count; i++)
            {
                var sh = sheets[i];
                var sheet = new StringBuilder("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView rightToLeft="1" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>""");
                if (sh.Widths is { Count: > 0 } widths)
                {
                    sheet.Append("<cols>");
                    for (var c = 0; c < widths.Count; c++)
                        sheet.Append(System.Globalization.CultureInfo.InvariantCulture,
                            $"<col min=\"{c + 1}\" max=\"{c + 1}\" width=\"{widths[c]}\" customWidth=\"1\"/>");
                    sheet.Append("</cols>");
                }
                sheet.Append("<sheetData>");
                var r = 1;
                AppendRow(sheet, r++, sh.Headers.Cast<object?>().ToList(), header: true);
                foreach (var row in sh.Rows)
                    AppendRow(sheet, r++, row, header: false);
                sheet.Append("</sheetData></worksheet>");
                Add(zip, $"xl/worksheets/sheet{i + 1}.xml", sheet.ToString());
            }
        }
        return buffer.ToArray();
    }

    /// <summary>اسم ورقة صالح في Excel: 31 حرفًا بلا الرموز الممنوعة.</summary>
    private static string SheetName(string name)
    {
        var clean = new string(name.Where(ch => ch is not ('[' or ']' or ':' or '*' or '?' or '/' or '\\')).ToArray());
        return clean.Length == 0 ? "Sheet" : clean.Length > 31 ? clean[..31] : clean;
    }

    private static void AppendRow(StringBuilder sheet, int r, IReadOnlyList<object?> values, bool header)
    {
        sheet.Append("<row r=\"").Append(r).Append("\">");
        for (var c = 0; c < values.Count; c++)
        {
            var reference = Column(c) + r;
            switch (values[c])
            {
                case null:
                    break;
                case decimal or int or long or double:
                    sheet.Append(System.Globalization.CultureInfo.InvariantCulture, $"<c r=\"{reference}\"><v>{Convert.ToString(values[c], System.Globalization.CultureInfo.InvariantCulture)}</v></c>");
                    break;
                case DateOnly d:
                    // تاريخ Excel: عدد الأيام منذ 1899-12-30.
                    sheet.Append(System.Globalization.CultureInfo.InvariantCulture, $"<c r=\"{reference}\" s=\"2\"><v>{d.DayNumber - new DateOnly(1899, 12, 30).DayNumber}</v></c>");
                    break;
                default:
                    var text = Clean(values[c]!.ToString()!);
                    sheet.Append(System.Globalization.CultureInfo.InvariantCulture, $"<c r=\"{reference}\" t=\"inlineStr\"{(header ? " s=\"1\"" : "")}><is><t xml:space=\"preserve\">{SecurityElement.Escape(text)}</t></is></c>");
                    break;
            }
        }
        sheet.Append("</row>");
    }

    /// <summary>
    /// يمنع حقن المعادلات عند فتح الملف (قيمة تبدأ بـ = أو + أو - أو @ تُعامل كنص)،
    /// ويحذف المحارف غير المسموحة في XML.
    /// </summary>
    private static string Clean(string value)
    {
        var text = new string(value.Where(ch => ch is '\t' or '\n' or '\r' || ch >= ' ').ToArray());
        return text.Length > 0 && text[0] is '=' or '+' or '-' or '@' ? "'" + text : text;
    }

    private static string Column(int index)
    {
        var name = "";
        for (index++; index > 0; index = (index - 1) / 26)
            name = (char)('A' + (index - 1) % 26) + name;
        return name;
    }

    private static void Add(ZipArchive zip, string path, string content)
    {
        using var writer = new StreamWriter(zip.CreateEntry(path, CompressionLevel.Optimal).Open(), new UTF8Encoding(false));
        writer.Write(content.Trim());
    }
}
