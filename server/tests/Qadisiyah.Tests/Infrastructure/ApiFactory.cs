using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Qadisiyah.Application;
using Qadisiyah.Application.Auth;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Security;

namespace Qadisiyah.Tests.Infrastructure;

/// <summary>
/// يشغّل الـ API كاملًا على قاعدة PostgreSQL حقيقية مخصصة للاختبار تُعاد
/// إنشاؤها مع كل تشغيل. قاعدة الاختبار تُحدد بـ <c>QADISIYAH_TEST_DB</c>.
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    public const string AdminPassword = "Bootstrap2026";

    /// <summary>مجلد مرفقات مؤقت لكل تشغيل اختبارات.</summary>
    public static readonly string AttachmentsRoot =
        Path.Combine(Path.GetTempPath(), "qadisiyah-test-attachments", Guid.NewGuid().ToString("N"));

    public static string ConnectionString =>
        Environment.GetEnvironmentVariable("QADISIYAH_TEST_DB")
        ?? "Host=localhost;Port=5432;Database=qadisiyah_test;Username=qadisiyah;Password=qadisiyah_dev";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        // UseSetting يصل للإعدادات قبل builder.Build() بخلاف ConfigureAppConfiguration،
        // وProgram يقرأ بعض الإعدادات مبكرًا.
        builder.UseSetting("ConnectionStrings:Default", ConnectionString);
        builder.UseSetting("Jwt:SigningKey", JwtOptions.DevelopmentSigningKey);
        builder.UseSetting("Bootstrap:AdminPassword", AdminPassword);
        builder.UseSetting("RateLimit:LoginPerMinute", "10000");
        builder.UseSetting("Attachments:Root", AttachmentsRoot);
        // قاعدة الاختبار تُنشأ في InitializeAsync قبل تشغيل الخادم.
        builder.UseSetting("Database:MigrateOnStartup", "false");
    }

    public async Task InitializeAsync()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(ConnectionString)
            .UseSnakeCaseNamingConvention()
            .Options;
        await using (var db = new AppDbContext(options))
            await db.Database.EnsureDeletedAsync();

        using var scope = Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<DbInitializer>().InitializeAsync();

        // عقد تسجيل العميل يتطلب خامة + Grade؛ Grade ثابت للاختبارات التي لا تختبر الخامات.
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var pp = await context.Materials.SingleAsync(m => m.Code == "PP");
        var grade = new Domain.Reference.Grade
        {
            MaterialId = pp.Id, Code = "FIXTURE-1", NormalizedCode = "fixture1", IsVerified = true,
        };
        context.Grades.Add(grade);
        await context.SaveChangesAsync();
        FixtureInterests = [new Application.Crm.InterestInput(pp.Id, GradeId: grade.Id)];
    }

    /// <summary>تهيئة قاعدة البيانات كما عند كل تشغيل للسيرفر (للتحقق من عدم التكرار).</summary>
    public async Task ReinitializeAsync()
    {
        using var scope = Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<DbInitializer>().InitializeAsync();
    }

    /// <summary>خامة + Grade كاملان لإنشاء عميل في الاختبارات.</summary>
    public static IReadOnlyList<Application.Crm.InterestInput> FixtureInterests { get; private set; } = [];

    /// <summary>الاهتمامات كما هي إن احتوت Grade كاملًا، وإلا يُضاف Grade الاختبار.</summary>
    public static IReadOnlyList<Application.Crm.InterestInput> WithGrade(
        IReadOnlyList<Application.Crm.InterestInput>? interests) =>
        interests is { } list && list.Any(i => !i.OpenSpec && (i.GradeId is not null || i.GradeCode is not null))
            ? list
            : [.. interests ?? [], .. FixtureInterests];

    async Task IAsyncLifetime.DisposeAsync() => await base.DisposeAsync();

    public async Task<T> WithDbAsync<T>(Func<AppDbContext, Task<T>> action)
    {
        using var scope = Services.CreateScope();
        return await action(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    public Task WithDbAsync(Func<AppDbContext, Task> action) =>
        WithDbAsync(async db => { await action(db); return true; });

    public async Task<Guid> CreateUserAsync(
        string username, string password, string role, bool mustChangePassword = false, bool active = true)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher>();
        var roleId = await db.Roles.Where(r => r.Code == role).Select(r => r.Id).SingleAsync();
        var user = new User
        {
            Username = User.NormalizeUsername(username),
            DisplayName = username,
            PasswordHash = hasher.Hash(password),
            MustChangePassword = mustChangePassword,
            IsActive = active,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        user.Roles.Add(new UserRole { RoleId = roleId });
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user.Id;
    }

    public async Task<AuthResponse> LoginAsync(string username, string password, Guid? deviceId = null)
    {
        using var client = CreateClient();
        var response = await client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(username, password, deviceId ?? Guid.CreateVersion7(), "test"));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
    }

    public HttpClient CreateClient(string accessToken)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", accessToken);
        return client;
    }
}

[CollectionDefinition(Name)]
public sealed class DatabaseCollection : ICollectionFixture<ApiFactory>
{
    public const string Name = "database";
}
