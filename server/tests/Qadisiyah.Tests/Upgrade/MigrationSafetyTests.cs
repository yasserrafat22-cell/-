using System.Text.RegularExpressions;

namespace Qadisiyah.Tests.Upgrade;

/// <summary>
/// التحديثات تراكمية: ترحيلات قاعدة البيانات تضيف ولا تحذف. أي ترحيل يحذف أو
/// يعيد تسمية جدول أو عمود يفشل هذا الاختبار، ويحتاج خطة ترحيل بيانات ونسخة
/// احتياطية وموافقة صريحة قبل قبوله.
/// </summary>
public sealed partial class MigrationSafetyTests
{
    [GeneratedRegex(@"protected override void Up\(MigrationBuilder migrationBuilder\)\s*\{(?<body>.*?)\n        \}\s*\n\s*/// <inheritdoc />\s*\n\s*protected override void Down", RegexOptions.Singleline)]
    private static partial Regex UpMethod();

    [GeneratedRegex(@"\.(DropTable|DropColumn|RenameColumn|RenameTable|DropIndex|AlterColumn|DropForeignKey|Sql)\(")]
    private static partial Regex DestructiveOperation();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();

    /// <summary>
    /// استثناءات معتمدة بالاسم فقط. فهرس عدم تكرار الـ Grade استُبدل بفهرس أوسع
    /// يشمل الشركة المصنّعة (كل البيانات التي حققت القديم تحقق الجديد)، ولا تُحذف بيانات.
    /// </summary>
    private static readonly Dictionary<string, string[]> ApprovedOperations = new()
    {
        ["CatalogManufacturersOrigins"] =
        [
            """
            migrationBuilder.DropIndex(
                            name: "ix_grades_material_id_normalized_code",
                            table: "grades");
            """,
        ],
    };

    private static string MigrationsDirectory()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "Qadisiyah.slnx")))
            dir = dir.Parent;
        return Path.Combine(dir!.FullName, "src", "Qadisiyah.Infrastructure", "Persistence", "Migrations");
    }

    [Fact]
    public void Migrations_only_add_to_the_schema()
    {
        var migrations = Directory.GetFiles(MigrationsDirectory(), "*.cs")
            .Where(f => !f.EndsWith(".Designer.cs", StringComparison.Ordinal)
                && !f.EndsWith("ModelSnapshot.cs", StringComparison.Ordinal))
            .ToList();
        Assert.NotEmpty(migrations);

        foreach (var file in migrations)
        {
            var match = UpMethod().Match(File.ReadAllText(file));
            Assert.True(match.Success, $"Cannot read Up() of {Path.GetFileName(file)}");
            var body = match.Groups["body"].Value;
            foreach (var (name, operations) in ApprovedOperations)
            {
                if (!Path.GetFileNameWithoutExtension(file).EndsWith("_" + name, StringComparison.Ordinal))
                    continue;
                foreach (var operation in operations)
                {
                    var normalized = Whitespace().Replace(operation, " ");
                    var bodyNormalized = Whitespace().Replace(body, " ");
                    Assert.Contains(normalized, bodyNormalized, StringComparison.Ordinal);
                    body = Whitespace().Replace(body, " ").Replace(normalized, "", StringComparison.Ordinal);
                }
            }
            var destructive = DestructiveOperation().Matches(body).Select(m => $"{Path.GetFileName(file)}: {m.Groups[1].Value}");
            Assert.Empty(destructive);
        }
    }
}
