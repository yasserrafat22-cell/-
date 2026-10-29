using Qadisiyah.Application.Admin;
using Qadisiyah.Application.Crm;

namespace Qadisiyah.Api.Endpoints;

/// <summary>النسخ الاحتياطي الكامل (للمدير) والتصدير إلى Excel (حسب الصلاحيات).</summary>
public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api/v1").RequireAuthorization().WithTags("Admin");

        // كلمة مرور النسخة في جسم الطلب فقط: لا تُحفظ ولا تظهر في الروابط أو السجلات.
        api.MapPost("/admin/backups", async (CreateBackupRequest request, IBackupService service, HttpContext http,
            CancellationToken ct) =>
        {
            var result = await service.CreateAsync(request.Password, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.Stream(result.Value!.Content, "application/octet-stream", result.Value.FileName);
        });

        api.MapGet("/export/parties", async (string role, ExportService service, HttpContext http, CancellationToken ct) =>
        {
            var result = await service.PartiesAsync(role, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.File(result.Value.Content,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", result.Value.FileName);
        });
    }
}
