using Microsoft.AspNetCore.Mvc;
using Qadisiyah.Application.Crm;

namespace Qadisiyah.Api.Endpoints;

/// <summary>«الإدخال السريع»: لصق/Excel بمسار تحقق واحد، «بانتظار الاستكمال»، سجل الدفعات، والتصدير الذكي.</summary>
public static class QuickEntryEndpoints
{
    private const string XlsxType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public static void MapQuickEntryEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api/v1/quick-entry").RequireAuthorization().WithTags("QuickEntry");

        api.MapPost("/validate", async (QuickBatchRequest request, QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.ValidateAsync(request, ct)));
        api.MapPost("/batches", async (QuickBatchRequest request, QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.CommitAsync(request, ct)));
        api.MapGet("/batches", async (QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.BatchesAsync(ct)));
        api.MapPost("/batches/{id:guid}/undo", async (Guid id, QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.UndoAsync(id, ct)));

        api.MapPost("/excel/read", async (HttpRequest request, QuickEntryService service, CancellationToken ct) =>
        {
            if (!request.HasFormContentType)
                return Problems.Validation("أرسل الملف كـ multipart/form-data");
            var form = await request.ReadFormAsync(ct);
            if (form.Files.GetFile("file") is not { } file)
                return Problems.Validation("الملف مطلوب");
            await using var content = file.OpenReadStream();
            return Problems.Ok(await service.ReadExcelAsync(content, file.FileName, ct));
        }).WithMetadata(new RequestSizeLimitAttribute(ImportService.MaxFileBytes + 1024 * 1024));

        api.MapGet("/pending", async ([AsParameters] PendingParameters p, QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.PendingAsync(p.ToQuery(), ct)));
        api.MapGet("/pending/export", async ([AsParameters] PendingParameters p, QuickEntryService service,
            HttpContext http, CancellationToken ct) =>
        {
            var result = await service.ExportPendingAsync(p.ToQuery(), ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.File(result.Value.Content, XlsxType, result.Value.FileName);
        });
        api.MapPut("/pending/{id:guid}", async (Guid id, PendingUpdate update, QuickEntryService service,
            CancellationToken ct) => Problems.Ok(await service.UpdateAsync(id, update, ct)));
        api.MapPost("/pending/{id:guid}/complete", async (Guid id, CompleteEntryRequest request, QuickEntryService service,
            CancellationToken ct) => Problems.Ok(await service.CompleteAsync(id, request, ct)));
        api.MapPost("/pending/{id:guid}/merge", async (Guid id, MergeEntryRequest request, QuickEntryService service,
            CancellationToken ct) => Problems.Ok(await service.MergeAsync(id, request, ct)));
        api.MapPost("/pending/{id:guid}/discard", async (Guid id, QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.DiscardAsync(id, ct)));

        api.MapPost("/export", async (ExportRequest request, QuickEntryService service, CancellationToken ct) =>
            Problems.Ok(await service.ExportAsync(request, ct)));
        api.MapPost("/export/excel", async (ExportRequest request, QuickEntryService service, HttpContext http,
            CancellationToken ct) =>
        {
            var result = await service.ExportExcelAsync(request, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "no-store";
            return Results.File(result.Value.Content, XlsxType, result.Value.FileName);
        });
    }
}

public sealed record PendingParameters(string? Q, string? Kind, Guid? BatchId, string? Issue, string? Status, int? Skip,
    int? Take)
{
    public PendingQuery ToQuery() => new(Q, Kind, BatchId, Issue, Status, Skip ?? 0, Take ?? 50);
}
