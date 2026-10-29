using Microsoft.AspNetCore.Mvc;
using Qadisiyah.Application.Admin;
using Qadisiyah.Application.Crm;

namespace Qadisiyah.Api.Endpoints;

/// <summary>النسخ الاحتياطي الكامل (للمدير) والتصدير إلى Excel (حسب الصلاحيات).</summary>
public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api/v1").RequireAuthorization().WithTags("Admin");

        // الطلب يحمل المفتاح العام المؤقت للجهاز فقط؛ كلمة المرور تبقى على الجهاز.
        api.MapPost("/admin/backups", async (CreateBackupRequest request, IBackupService service, HttpContext http,
            CancellationToken ct) =>
        {
            var result = await service.CreateAsync(request.PublicKey, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.Stream(result.Value!.Content, "application/octet-stream", result.Value.FileName);
        });

        api.MapGet("/parties/{id:guid}/supplier-matches", async (Guid id, MatchingService service, CancellationToken ct) =>
            Problems.Ok(await service.ForCustomerAsync(id, ct)));
        api.MapGet("/search", (string? q, Guid? materialId, Guid? manufacturerId, Guid? gradeId, SearchService service,
            CancellationToken ct) => service.SearchAsync(q, materialId, manufacturerId, gradeId, ct));
        api.MapGet("/follow-ups", (int? days, FollowUpService service, CancellationToken ct) =>
            service.ListAsync(days ?? 7, ct));
        api.MapGet("/reports/summary", async (DateOnly? from, DateOnly? to, ReportService service, CancellationToken ct) =>
            Problems.Ok(await service.SummaryAsync(from, to, ct)));

        api.MapGet("/reports/dashboard", async ([AsParameters] DashboardFilter filter, ReportService service,
            CancellationToken ct) => Problems.Ok(await service.DashboardAsync(filter, ct)));
        api.MapGet("/reports/dashboard/excel", async ([AsParameters] DashboardFilter filter, string? sections,
            ReportService service, HttpContext http, CancellationToken ct) =>
        {
            var result = await service.DashboardExcelAsync(filter,
                sections?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries), ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.File(result.Value.Content,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", result.Value.FileName);
        });
        api.MapPost("/share/authorize", async (ShareRequest request, ExportService service, CancellationToken ct) =>
            Problems.Ok(await service.AuthorizeShareAsync(request, ct)));
        api.MapPost("/export/search", async (SearchExportRequest request, ExportService service, HttpContext http,
            CancellationToken ct) =>
        {
            var result = await service.SearchAsync(request, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.File(result.Value.Content,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", result.Value.FileName);
        });
        // الاستيراد: معاينة لا تكتب شيئًا، ثم تنفيذ بمعرف ثابت من التطبيق (إعادة الإرسال لا تكرر).
        api.MapPost("/import/{kind}/{action:regex(^(preview|commit)$)}", async (string kind, string action,
            HttpRequest request, ImportService service, CancellationToken ct) =>
        {
            if (!request.HasFormContentType)
                return Problems.Validation("أرسل الملف كـ multipart/form-data");
            var form = await request.ReadFormAsync(ct);
            var file = form.Files.GetFile("file");
            if (file is null)
                return Problems.Validation("الملف مطلوب");
            Dictionary<string, int>? mapping = null;
            if (!string.IsNullOrWhiteSpace(form["mapping"]))
            {
                try
                {
                    mapping = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, int>>(form["mapping"]!);
                }
                catch (System.Text.Json.JsonException)
                {
                    return Problems.Validation("تعيين الأعمدة غير صالح");
                }
            }
            await using var content = file.OpenReadStream();
            if (action == "preview")
                return Problems.Ok(await service.PreviewAsync(kind, content, mapping, ct));
            return Guid.TryParse(form["importId"], out var importId)
                ? Problems.Ok(await service.CommitAsync(kind, importId, content, mapping, ct))
                : Problems.Validation("معرف عملية الاستيراد مطلوب");
        }).WithMetadata(new RequestSizeLimitAttribute(ImportService.MaxFileBytes + 1024 * 1024));
        api.MapGet("/import/templates/{kind}", (string kind, ImportService service) =>
        {
            if (!service.CanImport)
                return Problems.From(Application.Common.AppError.Forbidden());
            return ImportService.Template(kind) is { } t
                ? Results.File(t.Content, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", t.FileName)
                : Results.NotFound();
        });
        api.MapGet("/export/catalog", async (ImportService service, HttpContext http, CancellationToken ct) =>
        {
            var result = await service.ExportCatalogAsync(ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.File(result.Value.Content,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", result.Value.FileName);
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
