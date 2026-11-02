using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Tests.Infrastructure;

namespace Qadisiyah.Tests.Crm;

/// <summary>
/// الإدخال السريع 0.7.0 — المرحلة 2 (السيرفر): صف العناوين، تعيين الأعمدة دون تداخل، المنشأ،
/// أرقام الصفوف الأصلية، الأرقام المخزنة كأعداد، والأسماء البديلة للخامات في بيانات الكتالوج.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class QuickEntryPhase2Tests(ApiFactory api)
{
    private const string Password = "Crm12345a";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private async Task<HttpClient> AdminAsync()
    {
        var username = $"adm_{Guid.NewGuid():N}"[..20];
        await api.CreateUserAsync(username, Password, SystemRoles.SystemAdmin);
        return api.CreateClient((await api.LoginAsync(username, Password)).AccessToken);
    }

    private static string Fixture(string name)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var path = Path.Combine(dir.FullName, "testdata", "quick_entry", name);
            if (File.Exists(path))
                return File.ReadAllText(path);
        }
        throw new FileNotFoundException(name);
    }

    private static object? Cell(JsonElement v) => v.ValueKind switch
    {
        JsonValueKind.Number => v.GetInt64(),
        JsonValueKind.Null => null,
        _ => v.GetString(),
    };

    /// <summary>ملف xlsx من حالة: الصف الأول عناوين الكاتب، والصف null صف فارغ تمامًا.</summary>
    private static byte[] Workbook(JsonElement sheets) => XlsxWriter.WriteSheets([
        .. sheets.EnumerateArray().Select(sheet =>
        {
            var rows = sheet.GetProperty("rows").EnumerateArray().ToList();
            var width = rows.Where(r => r.ValueKind == JsonValueKind.Array).Max(r => r.GetArrayLength());
            IReadOnlyList<object?> Row(JsonElement r) => r.ValueKind == JsonValueKind.Null
                ? new object?[width]
                : r.EnumerateArray().Select(Cell).ToList();
            var first = rows[0].EnumerateArray().Select(v => v.GetString() ?? "").ToList();
            return new XlsxSheet(sheet.GetProperty("name").GetString()!, first, rows.Skip(1).Select(Row).ToList());
        }),
    ]);

    private static async Task<List<ExcelSheet>> ReadAsync(HttpClient client, byte[] file)
    {
        var content = new ByteArrayContent(file);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        var response = await client.PostAsync("/api/v1/quick-entry/excel/read",
            new MultipartFormDataContent { { content, "file", "cases.xlsx" } });
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<List<ExcelSheet>>(Json))!;
    }

    [Fact]
    public async Task Shared_excel_cases_detect_headers_mapping_and_source_rows()
    {
        var admin = await AdminAsync();
        var failures = new List<string>();
        foreach (var c in JsonDocument.Parse(Fixture("excel_cases.json")).RootElement.GetProperty("cases").EnumerateArray())
        {
            var id = c.GetProperty("id").GetString();
            var sheets = await ReadAsync(admin, Workbook(c.GetProperty("sheets")));
            foreach (var e in c.GetProperty("expected").EnumerateArray())
            {
                var name = e.GetProperty("sheet").GetString();
                var sheet = sheets.SingleOrDefault(s => s.Name == name);
                if (sheet is null)
                {
                    failures.Add($"{id} {name}: missing");
                    continue;
                }
                var headerRow = e.GetProperty("headerRow").GetInt32();
                if (sheet.HeaderRow != headerRow)
                    failures.Add($"{id} {name} headerRow: expected {headerRow}, got {sheet.HeaderRow}");
                var mapping = e.GetProperty("mapping").EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetInt32());
                var expectedMap = string.Join(",", mapping.OrderBy(x => x.Key).Select(x => $"{x.Key}={x.Value}"));
                var actualMap = string.Join(",", sheet.Mapping.OrderBy(x => x.Key).Select(x => $"{x.Key}={x.Value}"));
                if (expectedMap != actualMap)
                    failures.Add($"{id} {name} mapping: expected {expectedMap}, got {actualMap}");
                var rows = string.Join(",", e.GetProperty("sourceRows").EnumerateArray().Select(r => r.GetInt32()));
                var actualRows = string.Join(",", sheet.SourceRows ?? []);
                if (rows != actualRows)
                    failures.Add($"{id} {name} sourceRows: expected {rows}, got {actualRows}");
                if (e.TryGetProperty("phones", out var phones))
                {
                    var column = sheet.Mapping["phone"];
                    var actual = sheet.Rows.Select(r => PhoneNumber.Normalize(r[column]) is { } p && PhoneNumber.IsEgyptianMobile(p)
                        ? "0" + p[3..]
                        : r[column]);
                    var expected = phones.EnumerateArray().Select(p => p.GetString());
                    if (!expected.SequenceEqual(actual))
                        failures.Add($"{id} phones: expected {string.Join(",", expected)}, got {string.Join(",", actual)}");
                }
            }
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public async Task Origin_and_unverified_grade_from_excel_are_kept_without_catalog_links()
    {
        var admin = await AdminAsync();
        var phone = "010" + Random.Shared.NextInt64(10_000_000, 99_999_999);
        var code = "218" + Guid.NewGuid().ToString("N")[..4].ToUpperInvariant().Replace('0', 'Q');
        var row = new QuickEntryRow(Guid.CreateVersion7(), 7, "مورد", "مورد من إكسل", phone, "LLDPE", code, "SABIC",
            Origin: "بلد غير معروف");
        var result = await (await admin.PostAsJsonAsync("/api/v1/quick-entry/batches",
            new QuickBatchRequest(Guid.CreateVersion7(), QuickEntryMethods.Excel, QuickEntryAudience.Mixed, [row],
                "cases.xlsx — موردين"), Json)).Content.ReadFromJsonAsync<QuickBatchResult>(Json);
        var r = result!.Rows.Single();
        Assert.Equal(7, r.Row); // رقم الصف الأصلي في الملف
        Assert.Contains(QuickEntryIssues.GradeUnverified, r.Warnings!);
        Assert.Contains(QuickEntryIssues.OriginUnknown, r.Warnings!);
        Assert.Equal("completed", r.Status);
        var origin = await api.WithDbAsync(db => Task.FromResult(db.ImportEntries.Single(e => e.Id == row.Id).OriginText));
        Assert.Equal("بلد غير معروف", origin);
        var party = await (await admin.GetAsync($"/api/v1/parties/{row.Id}")).Content.ReadFromJsonAsync<PartyDetail>(Json);
        Assert.Equal(code, party!.Products.Single().UnverifiedGrade);
        Assert.Null(party.Products.Single().GradeId);
        Assert.Equal(0, await api.WithDbAsync(db =>
            Task.FromResult(db.Grades.Count(g => g.NormalizedCode == TextNormalizer.NormalizeCode(code)))));
    }

    [Fact]
    public async Task Reference_data_includes_material_aliases_for_the_device()
    {
        var admin = await AdminAsync();
        var refs = await admin.GetFromJsonAsync<ReferenceBundle>("/api/v1/reference", Json);
        var pp = refs!.Materials.Single(m => m.Code == "PP");
        Assert.Contains("بولي بروبلين", pp.Aliases!);
    }
}
