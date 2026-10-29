using Microsoft.AspNetCore.Mvc;
using Qadisiyah.Api.Security;
using Qadisiyah.Application.Crm;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Api.Endpoints;

/// <summary>
/// العملاء والموردون والتواصل والطلبات والتوريدات والأسعار. كل مسار يتطلب
/// دخولًا، والصلاحيات التفصيلية تُفحص داخل الخدمات لكل سجل.
/// </summary>
public static class CrmEndpoints
{
    public static void MapCrmEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api/v1").RequireAuthorization().WithTags("CRM");

        api.MapGet("/reference", (ReferenceService service, CancellationToken ct) => service.GetBundleAsync(ct));

        api.MapPost("/admin/materials", async (CreateMaterialRequest request, ReferenceService service, CancellationToken ct) =>
            Problems.Ok(await service.CreateMaterialAsync(request, ct)))
            .RequirePermission(Permissions.MasterDataManage);

        // ---------------- كتالوج الخامات ----------------
        var catalog = api.MapGroup("/catalog");
        catalog.MapPost("/materials", async (CreateMaterialTypeRequest request, CatalogService service, CancellationToken ct) =>
        {
            var result = await service.CreateMaterialTypeAsync(request, ct);
            return result.IsSuccess
                ? Results.Json(result.Value.Material, statusCode: result.Value.Created ? 201 : 200)
                : Problems.From(result.Error!);
        });
        catalog.MapGet("/manufacturers", async (CatalogService service, CancellationToken ct) =>
            Problems.Ok(await service.ListManufacturersAsync(ct)));
        catalog.MapPost("/manufacturers", async (CreateManufacturerRequest request, CatalogService service, CancellationToken ct) =>
        {
            var result = await service.CreateManufacturerAsync(request, ct);
            return result.IsSuccess
                ? Results.Json(result.Value.Manufacturer, statusCode: result.Value.Created ? 201 : 200)
                : Problems.From(result.Error!);
        });
        catalog.MapPut("/manufacturers/{id:guid}", async (Guid id, UpdateManufacturerRequest request, CatalogService service,
            CancellationToken ct) => Problems.Ok(await service.UpdateManufacturerAsync(id, request, ct)));
        catalog.MapGet("/grades", async (Guid? materialId, bool? pending, CatalogService service, CancellationToken ct) =>
            Problems.Ok(await service.ListGradesAsync(materialId, pending ?? false, ct)));
        catalog.MapPost("/grades", async (CreateGradeRequest request, CatalogService service, CancellationToken ct) =>
        {
            var result = await service.CreateGradeAsync(request, ct);
            return result.IsSuccess
                ? Results.Json(result.Value.Grade, statusCode: result.Value.Created ? 201 : 200)
                : Problems.From(result.Error!);
        });
        catalog.MapPut("/grades/{id:guid}", async (Guid id, UpdateGradeRequest request, CatalogService service,
            CancellationToken ct) => Problems.Ok(await service.UpdateGradeAsync(id, request, ct)));
        catalog.MapPost("/grades/{id:guid}/verify", async (Guid id, CatalogService service, CancellationToken ct) =>
            Problems.Ok(await service.VerifyGradeAsync(id, ct)));
        catalog.MapPost("/countries", async (CreateCountryRequest request, CatalogService service, CancellationToken ct) =>
            Problems.Ok(await service.CreateCountryAsync(request, ct)));

        // ---------------- العملاء والموردون ----------------
        api.MapGet("/parties", ([AsParameters] RegistryParameters p, RegistryService service, CancellationToken ct) =>
            service.ListAsync(new RegistryQuery(p.Role, p.Q, p.MaterialId, p.ManufacturerId, p.GradeId, p.CountryId,
                p.Favorites ?? false, p.Status, p.Skip ?? 0, p.Take ?? 30, p.Deleted ?? false), ct));

        api.MapPost("/parties/{id:guid}/interests", async (Guid id, InterestInput input, PartyService service,
            CancellationToken ct) => Problems.Ok(await service.AddInterestAsync(id, input, ct)));
        api.MapDelete("/parties/{id:guid}", async (Guid id, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.DeleteAsync(id, ct)));
        api.MapPost("/parties/{id:guid}/complete", async (Guid id, CompleteRequest request, PartyService service,
            CancellationToken ct) => Problems.Ok(await service.CompleteAsync(id, request, ct)));
        api.MapPost("/parties/{id:guid}/assign", async (Guid id, AssignRequest request, PartyService service,
            CancellationToken ct) => Problems.Ok(await service.AssignAsync(id, request, ct)));
        api.MapPost("/parties/{id:guid}/restore", async (Guid id, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.RestoreAsync(id, ct)));

        api.MapPut("/parties/{id:guid}/favorite", async (Guid id, RegistryService service, CancellationToken ct) =>
            Problems.Ok(await service.SetFavoriteAsync(id, true, ct)));
        api.MapDelete("/parties/{id:guid}/favorite", async (Guid id, RegistryService service, CancellationToken ct) =>
            Problems.Ok(await service.SetFavoriteAsync(id, false, ct)));
        api.MapGet("/parties/{id:guid}/locations", async (Guid id, LocationService service, CancellationToken ct) =>
            Problems.Ok(await service.ListAsync(id, ct)));
        api.MapPost("/parties/{id:guid}/locations", async (Guid id, LocationInput input, LocationService service,
            CancellationToken ct) => Problems.Ok(await service.CreateAsync(id, input, ct)));
        api.MapPut("/locations/{id:guid}", async (Guid id, LocationInput input, LocationService service, CancellationToken ct) =>
            Problems.Ok(await service.UpdateAsync(id, input, ct)));
        api.MapPost("/locations/{id:guid}/restore", async (Guid id, LocationService service, CancellationToken ct) =>
            Problems.Ok(await service.RestoreAsync(id, ct)));
        api.MapDelete("/locations/{id:guid}", async (Guid id, LocationService service, CancellationToken ct) =>
            Problems.Ok(await service.RemoveAsync(id, ct)));

        // ---------------- المرفقات ----------------
        api.MapGet("/parties/{id:guid}/contacts", async (Guid id, ContactService service, CancellationToken ct) =>
            Problems.Ok(await service.ListAsync(id, ct)));
        api.MapPost("/parties/{id:guid}/contacts", async (Guid id, ContactInput input, ContactService service,
            CancellationToken ct) => Problems.Ok(await service.CreateAsync(id, input, ct)));
        api.MapPut("/contacts/{id:guid}", async (Guid id, ContactInput input, ContactService service, CancellationToken ct) =>
            Problems.Ok(await service.UpdateAsync(id, input, ct)));
        api.MapDelete("/contacts/{id:guid}", async (Guid id, ContactService service, CancellationToken ct) =>
            Problems.Ok(await service.RemoveAsync(id, ct)));

        catalog.MapPost("/grades/{id:guid}/files", async (Guid id, HttpRequest request, GradeFileService service,
            CancellationToken ct) =>
        {
            if (!request.HasFormContentType)
                return Problems.From(Application.Common.AppError.Validation("أرسل الملف كـ multipart/form-data"));
            var form = await request.ReadFormAsync(ct);
            var file = form.Files.GetFile("file");
            if (file is null
                || !Guid.TryParse(form["id"], out var fileId)
                || !Enum.TryParse<Domain.Crm.GradeFileKind>(form["kind"], ignoreCase: true, out var kind))
                return Problems.From(Application.Common.AppError.Validation("بيانات الملف غير مكتملة"));
            await using var content = file.OpenReadStream();
            var result = await service.UploadAsync(id, fileId, kind, file.FileName, file.Length, content, ct);
            return result.IsSuccess
                ? Results.Json(result.Value.File, statusCode: result.Value.Created ? 201 : 200)
                : Problems.From(result.Error!);
        }).WithMetadata(new RequestSizeLimitAttribute(AttachmentService.MaxPdfBytes + 1024 * 1024));
        catalog.MapGet("/grade-files/{id:guid}/content", async (Guid id, HttpContext http, GradeFileService service,
            CancellationToken ct) =>
        {
            var result = await service.OpenAsync(id, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            http.Response.Headers.CacheControl = "private, no-store";
            http.Response.Headers.ContentDisposition =
                $"inline; filename*=UTF-8''{Uri.EscapeDataString(result.Value!.FileName)}";
            http.Response.Headers.XContentTypeOptions = "nosniff";
            return Results.Stream(result.Value.Content, result.Value.ContentType);
        });
        catalog.MapDelete("/grade-files/{id:guid}", async (Guid id, GradeFileService service, CancellationToken ct) =>
            Problems.Ok(await service.RemoveAsync(id, ct)));

        api.MapGet("/parties/{id:guid}/attachments", async (Guid id, AttachmentService service, CancellationToken ct) =>
            Problems.Ok(await service.ListAsync(id, ct)));
        api.MapPost("/parties/{id:guid}/attachments", async (Guid id, HttpRequest request, AttachmentService service,
            CancellationToken ct) =>
        {
            if (!request.HasFormContentType)
                return Problems.From(Application.Common.AppError.Validation("أرسل الملف كـ multipart/form-data"));
            var form = await request.ReadFormAsync(ct);
            var file = form.Files.GetFile("file");
            if (file is null
                || !Guid.TryParse(form["id"], out var attachmentId)
                || !Enum.TryParse<Domain.Crm.AttachmentKind>(form["kind"], ignoreCase: true, out var kind))
                return Problems.From(Application.Common.AppError.Validation("بيانات الملف غير مكتملة"));
            static Guid? OptionalId(string? v) => Guid.TryParse(v, out var g) ? g : null;
            await using var content = file.OpenReadStream();
            var result = await service.UploadAsync(id, new AttachmentUpload(attachmentId, kind, file.FileName, file.Length,
                content, OptionalId(form["gradeId"]), OptionalId(form["materialId"]), form["caption"]), ct);
            return result.IsSuccess
                ? Results.Json(result.Value.Attachment, statusCode: result.Value.Created ? 201 : 200)
                : Problems.From(result.Error!);
        }).WithMetadata(new RequestSizeLimitAttribute(AttachmentService.MaxPdfBytes + 1024 * 1024));
        api.MapGet("/attachments/{id:guid}/content", async (Guid id, HttpContext http, AttachmentService service,
            CancellationToken ct) =>
        {
            var result = await service.OpenAsync(id, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            // ملفات خاصة: لا روابط عامة ولا تخزين مؤقت في الوسطاء.
            http.Response.Headers.CacheControl = "private, no-store";
            http.Response.Headers.ContentDisposition =
                $"inline; filename*=UTF-8''{Uri.EscapeDataString(result.Value!.FileName)}";
            http.Response.Headers.XContentTypeOptions = "nosniff";
            return Results.Stream(result.Value.Content, result.Value.ContentType);
        });
        api.MapPost("/attachments/{id:guid}/restore", async (Guid id, AttachmentService service, CancellationToken ct) =>
            Problems.Ok(await service.RestoreAsync(id, ct)));
        api.MapDelete("/attachments/{id:guid}", async (Guid id, AttachmentService service, CancellationToken ct) =>
            Problems.Ok(await service.RemoveAsync(id, ct)));

        api.MapGet("/audit", async (string? action, Guid? entityId, Guid? userId, int? skip, int? take, AuditService service,
            CancellationToken ct) => Problems.Ok(await service.ListAsync(action, entityId, userId, skip ?? 0, take ?? 50, ct)));

        api.MapGet("/parties/{id:guid}/history", async (Guid id, int? take, RegistryService service, CancellationToken ct) =>
            Problems.Ok(await service.HistoryAsync(id, take ?? 30, ct)));

        api.MapPost("/parties", async (CreatePartyRequest request, PartyService service, CancellationToken ct) =>
        {
            var result = await service.CreateAsync(request, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            var r = result.Value!;
            // المندوب الذي يضيف موردًا لا يحصل على بياناته: تأكيد التسجيل فقط.
            object body = r.Party is { } party ? party : new { r.Id, r.Name, Visible = false };
            return r.Created ? Results.Created($"/api/v1/parties/{r.Id}", body) : Results.Ok(body);
        });

        api.MapGet("/parties/{id:guid}", async (Guid id, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.GetAsync(id, ct)));

        api.MapPut("/parties/{id:guid}", async (Guid id, UpdatePartyRequest request, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.UpdateAsync(id, request, ct)));

        api.MapPost("/parties/{id:guid}/roles", async (Guid id, AddRoleRequest request, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.AddRoleAsync(id, request, ct)));

        api.MapPost("/parties/{id:guid}/products", async (Guid id, ProductInput request, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.AddProductAsync(id, request, ct)));

        api.MapGet("/supplier-products/{id:guid}/quotes", async (Guid id, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.ListQuotesAsync(id, ct)));

        api.MapPost("/supplier-products/{id:guid}/quotes", async (Guid id, CreateQuoteRequest request, PartyService service, CancellationToken ct) =>
            Problems.Ok(await service.AddQuoteAsync(id, request, ct)));

        // ---------------- التواصل ----------------
        api.MapGet("/parties/{id:guid}/interactions", async (Guid id, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.ListInteractionsAsync(id, ct)));

        api.MapPost("/parties/{id:guid}/interactions", async (Guid id, CreateInteractionRequest request, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.AddInteractionAsync(id, request, ct)));

        // ---------------- الطلبات ----------------
        api.MapGet("/parties/{id:guid}/orders", async (Guid id, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.ListOrdersAsync(id, ct)));

        api.MapPost("/orders", async (CreateOrderRequest request, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.CreateOrderAsync(request, ct)));

        api.MapGet("/orders/{id:guid}", async (Guid id, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.GetOrderAsync(id, ct)));

        api.MapPost("/orders/{id:guid}/stage", async (Guid id, ChangeStageRequest request, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.ChangeOrderStageAsync(id, request, ct)));

        api.MapPost("/orders/{id:guid}/hold", async (Guid id, SetHoldRequest request, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.SetOrderHoldAsync(id, request, ct)));

        // ---------------- التوريدات ----------------
        api.MapGet("/parties/{id:guid}/supplies", async (Guid id, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.ListSuppliesAsync(id, ct)));

        api.MapPost("/supplies", async (CreateSupplyRequest request, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.CreateSupplyAsync(request, ct)));

        api.MapPost("/supplies/{id:guid}/status", async (Guid id, ChangeSupplyStatusRequest request, ActivityService service, CancellationToken ct) =>
            Problems.Ok(await service.ChangeSupplyStatusAsync(id, request, ct)));
    }
}

/// <summary>معاملات بحث السجل في الرابط.</summary>
public sealed record RegistryParameters(
    string? Role,
    string? Q,
    Guid? MaterialId,
    Guid? ManufacturerId,
    Guid? GradeId,
    Guid? CountryId,
    bool? Favorites,
    Qadisiyah.Domain.Crm.PartyStatus? Status,
    int? Skip,
    int? Take,
    bool? Deleted);
