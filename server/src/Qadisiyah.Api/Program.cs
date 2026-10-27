using System.Threading.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Api.Endpoints;
using Qadisiyah.Api.Security;
using Qadisiyah.Infrastructure;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Security;

var builder = WebApplication.CreateBuilder(args);

var jwt = builder.Configuration.GetSection(JwtOptions.Section).Get<JwtOptions>() ?? new JwtOptions();
if (jwt.SigningKey.Length < 32)
    throw new InvalidOperationException("Jwt:SigningKey must be at least 32 characters.");
if (!builder.Environment.IsDevelopment() && !builder.Environment.IsEnvironment("Testing")
    && jwt.SigningKey == JwtOptions.DevelopmentSigningKey)
    throw new InvalidOperationException("The development JWT signing key cannot be used outside Development.");

builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddAppAuthentication(jwt);
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
app.MapAuthEndpoints();

await app.RunAsync();

/// <summary>مرئي لاختبارات التكامل عبر WebApplicationFactory.</summary>
public partial class Program;
