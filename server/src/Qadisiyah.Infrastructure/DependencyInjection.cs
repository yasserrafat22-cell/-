using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Qadisiyah.Application;
using Qadisiyah.Application.Auth;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Infrastructure.Persistence;
using Qadisiyah.Infrastructure.Security;
using Qadisiyah.Infrastructure.Storage;

namespace Qadisiyah.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Default")
            ?? throw new InvalidOperationException("ConnectionStrings:Default is not configured.");

        services.AddDbContext<AppDbContext>(o => o
            .UseNpgsql(connectionString)
            .UseSnakeCaseNamingConvention());
        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<AppDbContext>());

        services.AddSingleton(configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions());
        services.AddSingleton(configuration.GetSection(JwtOptions.Section).Get<JwtOptions>() ?? new JwtOptions());
        services.AddSingleton(configuration.GetSection(BootstrapOptions.Section).Get<BootstrapOptions>() ?? new BootstrapOptions());

        var attachments = configuration.GetSection(AttachmentOptions.Section).Get<AttachmentOptions>() ?? new AttachmentOptions();
        if (string.IsNullOrWhiteSpace(attachments.Root))
            attachments.Root = Path.Combine(Directory.GetCurrentDirectory(), "App_Data", "attachments");
        services.AddSingleton(attachments);
        services.AddSingleton<IFileStore, LocalFileStore>();

        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IPasswordHasher, PasswordHasher>();
        services.AddSingleton<IAccessTokenIssuer, JwtAccessTokenIssuer>();
        services.AddScoped<AuthService>();
        services.AddScoped<ReferenceService>();
        services.AddScoped<MaterialSpecs>();
        services.AddScoped<PartySummaries>();
        services.AddScoped<RegistryService>();
        services.AddScoped<AuditService>();
        services.AddScoped<LocationService>();
        services.AddScoped<AttachmentService>();
        services.AddScoped<CatalogService>();
        services.AddScoped<PartyAccess>();
        services.AddScoped<PartyService>();
        services.AddScoped<ActivityService>();
        services.AddScoped<DbInitializer>();
        return services;
    }
}
