using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Api.Endpoints;
using Qadisiyah.Api.Security;
using Qadisiyah.Application.Common;
using Qadisiyah.Infrastructure;
using Qadisiyah.Infrastructure.Backup;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Security;

// فك تشفير نسخة احتياطية من التطبيق إلى ملفات يقبلها restore-trial.sh (لا يشغل السيرفر):
// dotnet Qadisiyah.Api.dll decrypt-backup <ملف.qbk> <مجلد الإخراج>  (كلمة المرور من QBK_PASSWORD أو المدخل)
if (args is ["decrypt-backup", var backupFile, var outputDir])
    return await BackupCli.DecryptAsync(backupFile, outputDir);

var builder = WebApplication.CreateBuilder(args);

var jwt = builder.Configuration.GetSection(JwtOptions.Section).Get<JwtOptions>() ?? new JwtOptions();
if (jwt.SigningKey.Length < 32)
    throw new InvalidOperationException("Jwt:SigningKey must be at least 32 characters.");
if (!builder.Environment.IsDevelopment() && !builder.Environment.IsEnvironment("Testing")
    && jwt.SigningKey == JwtOptions.DevelopmentSigningKey)
    throw new InvalidOperationException("The development JWT signing key cannot be used outside Development.");

builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddAppAuthentication(jwt);
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUser, HttpCurrentUser>();
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));
builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy(AuthEndpoints.LoginRateLimit, http => RateLimitPartition.GetFixedWindowLimiter(
        http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = builder.Configuration.GetValue("RateLimit:LoginPerMinute", 20),
            Window = TimeSpan.FromMinutes(1),
        }));
});

var app = builder.Build();

if (app.Configuration.GetValue("Database:MigrateOnStartup", true))
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<DbInitializer>().InitializeAsync();
}

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapHealthChecks("/health");
app.MapGet("/health/db", async (AppDbContext db, CancellationToken ct) =>
    await db.Database.CanConnectAsync(ct) ? Results.Ok("ok") : Results.StatusCode(StatusCodes.Status503ServiceUnavailable));
// للتحقق بعد التحديث: إصدار السيرفر وآخر ترحيل طُبق على قاعدة البيانات.
app.MapGet("/api/v1/version", async (AppDbContext db, CancellationToken ct) => Results.Ok(new
{
    version = typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
        .Split('+')[0],
    schema = (await db.Database.GetAppliedMigrationsAsync(ct)).LastOrDefault(),
}));
app.MapAuthEndpoints();
app.MapCrmEndpoints();
app.MapAdminEndpoints();

await app.RunAsync();
return 0;

/// <summary>مرئي لاختبارات التكامل عبر WebApplicationFactory.</summary>
public partial class Program;
