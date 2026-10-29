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
                p.Favorites ?? false, p.Status, p.Skip ?? 0, p.Take ?? 30), ct));

        api.MapPut("/parties/{id:guid}/favorite", async (Guid id, RegistryService service, CancellationToken ct) =>
            Problems.Ok(await service.SetFavoriteAsync(id, true, ct)));
        api.MapDelete("/parties/{id:guid}/favorite", async (Guid id, RegistryService service, CancellationToken ct) =>
            Problems.Ok(await service.SetFavoriteAsync(id, false, ct)));
        api.MapGet("/parties/{id:guid}/history", async (Guid id, int? take, RegistryService service, CancellationToken ct) =>
            Problems.Ok(await service.HistoryAsync(id, take ?? 30, ct)));

        api.MapPost("/parties", async (CreatePartyRequest request, PartyService service, CancellationToken ct) =>
        {
            var result = await service.CreateAsync(request, ct);
            if (!result.IsSuccess)
                return Problems.From(result.Error!);
            var (party, created) = result.Value;
            return created ? Results.Created($"/api/v1/parties/{party.Id}", party) : Results.Ok(party);
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
    int? Take);
