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
            var destructive = DestructiveOperation().Matches(match.Groups["body"].Value).Select(m => m.Groups[1].Value);
            Assert.Empty(destructive);
        }
    }
}
