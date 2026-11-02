using System.Text.Json;
using Qadisiyah.Domain.Common;

namespace Qadisiyah.Tests.Crm;

/// <summary>
/// حالات «الإدخال السريع» 0.7.0 المشتركة مع التطبيق (<c>testdata/quick_entry</c>). سلامة الملفات وقواعد
/// الأرقام (السيرفر هو المرجع) تُختبر الآن؛ حالات التحقق وExcel والتنظيف تُفعَّل في مراحلها.
/// </summary>
public sealed class QuickEntryFixtureTests
{
    private static readonly string Dir = FindDir();
    private static readonly string[] Statuses = ["ready", "incomplete", "needs_review"];
    private static readonly string[] CaseFiles = ["paste_cases.json", "validation_cases.json", "excel_cases.json"];

    private static string FindDir()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "testdata", "quick_entry");
            if (Directory.Exists(candidate))
                return candidate;
        }
        throw new DirectoryNotFoundException("testdata/quick_entry غير موجود");
    }

    private static JsonElement Load(string name) =>
        JsonDocument.Parse(File.ReadAllText(Path.Combine(Dir, name))).RootElement;

    public static TheoryData<string, string?> PhoneCases()
    {
        var data = new TheoryData<string, string?>();
        foreach (var c in Load("phone_cases.json").GetProperty("cases").EnumerateArray())
            data.Add(c.GetProperty("input").GetString()!, c.GetProperty("local").GetString());
        return data;
    }

    [Theory]
    [MemberData(nameof(PhoneCases))]
    public void Phone_cases_match_the_server_rules(string input, string? local)
    {
        var e164 = PhoneNumber.Normalize(input);
        var actual = PhoneNumber.IsEgyptianMobile(e164) ? "0" + e164![3..] : null;
        Assert.Equal(local, actual);
    }

    [Fact]
    public void Case_files_are_consistent()
    {
        var catalog = Load("catalog.json");
        var materials = catalog.GetProperty("materials").EnumerateArray().ToList();
        var materialIds = materials.Select(m => m.GetProperty("id").GetString()).ToHashSet();
        var gradeIds = materials.SelectMany(m => m.GetProperty("grades").EnumerateArray())
            .Select(g => g.GetProperty("id").GetString()).ToHashSet();

        foreach (var file in CaseFiles)
        {
            var ids = Load(file).GetProperty("cases").EnumerateArray().Select(c => c.GetProperty("id").GetString()).ToList();
            Assert.Equal(ids.Count, ids.Distinct().Count());
        }

        foreach (var c in Load("validation_cases.json").GetProperty("cases").EnumerateArray())
        {
            var e = c.GetProperty("expected");
            var status = e.GetProperty("status").GetString();
            Assert.Contains(status, Statuses);
            Assert.Equal(status == "incomplete", e.GetProperty("blocking").GetArrayLength() > 0);
            if (e.GetProperty("materialId").GetString() is { } m)
                Assert.Contains(m, materialIds);
            if (e.GetProperty("gradeId").GetString() is { } g)
                Assert.Contains(g, gradeIds);
        }
    }
}
