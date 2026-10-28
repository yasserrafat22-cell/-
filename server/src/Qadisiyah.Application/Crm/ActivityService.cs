using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Crm;

public sealed record CreateInteractionRequest(
    Guid Id,
    ContactChannel Channel,
    Guid OutcomeId,
    DateTimeOffset? OccurredAt = null,
    string? Notes = null,
    DateTimeOffset? NextFollowUpAt = null,
    bool Remind = false);

public sealed record InteractionDto(Guid Id, ContactChannel Channel, Guid OutcomeId, string OutcomeName,
    string? OutcomeSemantic, DateTimeOffset OccurredAt, string? Notes, DateTimeOffset? NextFollowUpAt, bool Remind,
    bool FollowUpDone, string CreatedByName);

public sealed record LineInput(Guid MaterialId, decimal Quantity, Guid UnitId, string? GradeCode = null);

public sealed record LineDto(Guid Id, Guid MaterialId, string MaterialCode, Guid? GradeId, string? GradeCode,
    decimal Quantity, Guid UnitId, string UnitCode, decimal QuantityKg);

public sealed record CreateOrderRequest(
    Guid Id,
    Guid CustomerId,
    DateOnly OrderDate,
    IReadOnlyList<LineInput> Lines,
    OrderStage Stage = OrderStage.Inquiry,
    Guid? RepresentativeId = null,
    string? Notes = null);

public sealed record OrderDto(Guid Id, Guid CustomerId, DateOnly OrderDate, OrderStage Stage, bool OnHold,
    Guid? RepresentativeId, string? Notes, IReadOnlyList<LineDto> Lines, decimal TotalKg, uint Version,
    DateTimeOffset CreatedAt);

public sealed record ChangeStageRequest(OrderStage Stage, uint Version);

public sealed record SetHoldRequest(bool OnHold, uint Version);

public sealed record CreateSupplyRequest(
    Guid Id,
    Guid SupplierId,
    DateOnly SupplyDate,
    IReadOnlyList<LineInput> Lines,
    SupplyStatus Status = SupplyStatus.Received,
    string? Notes = null);

public sealed record SupplyDto(Guid Id, Guid SupplierId, DateOnly SupplyDate, SupplyStatus Status, string? Notes,
    IReadOnlyList<LineDto> Lines, decimal TotalKg, uint Version, DateTimeOffset CreatedAt);

public sealed record ChangeSupplyStatusRequest(SupplyStatus Status, uint Version);

/// <summary>التواصل والطلبات والتوريدات المرتبطة بعميل أو مورد.</summary>
public sealed class ActivityService(
    IAppDbContext db,
    ICurrentUser user,
    PartyAccess access,
    ReferenceService reference,
    TimeProvider clock)
{
    private const int MaxLines = 50;
    private static readonly TimeSpan ClockSkew = TimeSpan.FromMinutes(10);

    // ---------------- التواصل ----------------

    public async Task<Result<InteractionDto>> AddInteractionAsync(Guid partyId, CreateInteractionRequest request, CancellationToken ct)
    {
        var loaded = await access.LoadEditableAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;

        var existing = await db.Interactions.AsNoTracking().FirstOrDefaultAsync(i => i.Id == request.Id, ct);
        if (existing is not null)
            return existing.CreatedBy == user.UserId && existing.PartyId == partyId
                ? (await ListInteractionsAsync(partyId, ct)).Value!.First(i => i.Id == existing.Id)
                : AppError.Conflict("interaction.id_taken", "معرف السجل مستخدم بالفعل");

        if (request.Id == Guid.Empty || !Enum.IsDefined(request.Channel))
            return AppError.Validation("نوع التواصل مطلوب");
        var outcome = await db.LookupItems.AsNoTracking().FirstOrDefaultAsync(l =>
            l.Id == request.OutcomeId && l.Category == LookupCategories.ContactOutcome && l.IsActive, ct);
        if (outcome is null || !AppliesTo(outcome.AppliesTo, party))
            return AppError.Validation("نتيجة التواصل مطلوبة");

        var now = clock.GetUtcNow();
        var occurredAt = request.OccurredAt ?? now;
        if (occurredAt > now + ClockSkew)
            return AppError.Validation("وقت التواصل لا يمكن أن يكون في المستقبل");
        if (request.NextFollowUpAt is { } next && next <= occurredAt)
            return AppError.Validation("موعد المتابعة القادمة يجب أن يكون بعد وقت التواصل");

        // تواصل جديد يُغلق المتابعات السابقة المفتوحة لنفس الطرف.
        await db.Interactions
            .Where(i => i.PartyId == partyId && !i.FollowUpDone && i.NextFollowUpAt != null && i.OccurredAt <= occurredAt)
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.FollowUpDone, true), ct);

        var interaction = new Interaction
        {
            Id = request.Id,
            PartyId = partyId,
            Channel = request.Channel,
            OutcomeId = outcome.Id,
            OccurredAt = occurredAt,
            Notes = PartyService.Clean(request.Notes, 300),
            NextFollowUpAt = request.NextFollowUpAt,
            Remind = request.Remind && request.NextFollowUpAt is not null,
        };
        interaction.Stamp(user.UserId, now);
        db.Interactions.Add(interaction);
        db.Audit(user, clock, "interaction.created", "party", partyId,
            new { interaction.Id, channel = request.Channel.ToString(), outcome = outcome.Code });
        await db.SaveChangesAsync(ct);
        return (await ListInteractionsAsync(partyId, ct)).Value!.First(i => i.Id == interaction.Id);
    }

    public async Task<Result<IReadOnlyList<InteractionDto>>> ListInteractionsAsync(Guid partyId, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var items = await (
            from i in db.Interactions.AsNoTracking()
            join o in db.LookupItems.AsNoTracking() on i.OutcomeId equals o.Id
            join u in db.Users.AsNoTracking() on i.CreatedBy equals u.Id into users
            from u in users.DefaultIfEmpty()
            where i.PartyId == partyId && i.DeletedAt == null
            orderby i.OccurredAt descending
            select new InteractionDto(i.Id, i.Channel, i.OutcomeId, o.NameAr, o.Semantic, i.OccurredAt, i.Notes,
                i.NextFollowUpAt, i.Remind, i.FollowUpDone, u != null ? u.DisplayName : ""))
            .Take(200)
            .ToListAsync(ct);
        return items;
    }

    // ---------------- الطلبات ----------------

    public async Task<Result<OrderDto>> CreateOrderAsync(CreateOrderRequest request, CancellationToken ct)
    {
        if (!user.Has(Permissions.OrdersManage))
            return AppError.Forbidden();
        var loaded = await access.LoadEditableAsync(request.CustomerId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (!loaded.Value!.IsCustomer)
            return AppError.Validation("الطلبات تُسجل للعملاء فقط");

        var existing = await db.Orders.AsNoTracking().FirstOrDefaultAsync(o => o.Id == request.Id, ct);
        if (existing is not null)
            return existing.CreatedBy == user.UserId && existing.CustomerId == request.CustomerId
                ? (await GetOrderAsync(existing.Id, ct))
                : AppError.Conflict("order.id_taken", "معرف الطلب مستخدم بالفعل");

        if (request.Id == Guid.Empty || !Enum.IsDefined(request.Stage))
            return AppError.Validation("بيانات الطلب غير مكتملة");
        if (request.RepresentativeId is { } rep && !await db.Representatives.AnyAsync(r => r.Id == rep, ct))
            return AppError.Validation("المندوب غير معروف");

        var lines = await BuildLinesAsync(request.Lines, ct);
        if (lines.Error is not null)
            return lines.Error;

        var now = clock.GetUtcNow();
        var order = new Order
        {
            Id = request.Id,
            CustomerId = request.CustomerId,
            OrderDate = request.OrderDate,
            Stage = request.Stage,
            RepresentativeId = request.RepresentativeId ?? loaded.Value.RepresentativeId,
            Notes = PartyService.Clean(request.Notes, 300),
        };
        order.Stamp(user.UserId, now);
        foreach (var (material, grade, quantity, unit, kg) in lines.Value!)
            order.Lines.Add(new OrderLine
            {
                LineNo = order.Lines.Count + 1,
                MaterialId = material,
                GradeId = grade,
                Quantity = quantity,
                UnitId = unit,
                QuantityKg = kg,
            });
        db.Orders.Add(order);
        db.OrderStageChanges.Add(new OrderStageChange { OrderId = order.Id, ToStage = order.Stage, At = now, By = user.UserId });
        db.Audit(user, clock, "order.created", "order", order.Id, new { order.CustomerId, stage = order.Stage.ToString() });
        await db.SaveChangesAsync(ct);
        return await GetOrderAsync(order.Id, ct);
    }

    public async Task<Result<OrderDto>> ChangeOrderStageAsync(Guid orderId, ChangeStageRequest request, CancellationToken ct)
    {
        var (order, error) = await LoadOrderForEditAsync(orderId, request.Version, ct);
        if (error is not null)
            return error;
        if (!Enum.IsDefined(request.Stage) || !OrderStages.CanTransition(order!.Stage, request.Stage))
            return AppError.Validation($"لا يمكن نقل الطلب من «{StageName(order!.Stage)}» إلى «{StageName(request.Stage)}»",
                "order.invalid_transition");

        var now = clock.GetUtcNow();
        db.OrderStageChanges.Add(new OrderStageChange
        {
            OrderId = order.Id, FromStage = order.Stage, ToStage = request.Stage, At = now, By = user.UserId,
        });
        db.Audit(user, clock, "order.stage_changed", "order", order.Id,
            new { from = order.Stage.ToString(), to = request.Stage.ToString() });
        order.Stage = request.Stage;
        if (OrderStages.IsTerminal(order.Stage))
            order.OnHold = false;
        order.Touch(user.UserId, now);
        return await SaveOrderAsync(order, ct);
    }

    public async Task<Result<OrderDto>> SetOrderHoldAsync(Guid orderId, SetHoldRequest request, CancellationToken ct)
    {
        var (order, error) = await LoadOrderForEditAsync(orderId, request.Version, ct);
        if (error is not null)
            return error;
        if (OrderStages.IsTerminal(order!.Stage) && request.OnHold)
            return AppError.Validation("لا يمكن تعليق طلب مكتمل أو ملغي", "order.invalid_transition");

        order.OnHold = request.OnHold;
        order.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "order.hold_changed", "order", order.Id, new { request.OnHold });
        return await SaveOrderAsync(order, ct);
    }

    public async Task<Result<OrderDto>> GetOrderAsync(Guid orderId, CancellationToken ct)
    {
        var order = await db.Orders.AsNoTracking().Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == orderId && o.DeletedAt == null, ct);
        if (order is null || !(await access.LoadVisibleAsync(order.CustomerId, ct)).IsSuccess)
            return AppError.NotFound();
        return (await ToOrderDtosAsync([order], ct))[0];
    }

    public async Task<Result<IReadOnlyList<OrderDto>>> ListOrdersAsync(Guid customerId, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(customerId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var orders = await db.Orders.AsNoTracking().Include(o => o.Lines)
            .Where(o => o.CustomerId == customerId && o.DeletedAt == null)
            .OrderByDescending(o => o.OrderDate).ThenByDescending(o => o.CreatedAt)
            .Take(200).ToListAsync(ct);
        return await ToOrderDtosAsync(orders, ct);
    }

    private async Task<(Order?, AppError?)> LoadOrderForEditAsync(Guid orderId, uint version, CancellationToken ct)
    {
        if (!user.Has(Permissions.OrdersManage))
            return (null, AppError.Forbidden());
        var order = await db.Orders.Include(o => o.Lines).FirstOrDefaultAsync(o => o.Id == orderId && o.DeletedAt == null, ct);
        if (order is null)
            return (null, AppError.NotFound());
        var party = await access.LoadEditableAsync(order.CustomerId, ct);
        if (!party.IsSuccess)
            return (null, party.Error);
        if (order.Version != version)
            return (null, AppError.StaleVersion());
        db.SetOriginalVersion(order, version);
        return (order, null);
    }

    private async Task<Result<OrderDto>> SaveOrderAsync(Order order, CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return AppError.StaleVersion();
        }
        return await GetOrderAsync(order.Id, ct);
    }

    private async Task<List<OrderDto>> ToOrderDtosAsync(List<Order> orders, CancellationToken ct)
    {
        var lineDtos = await ToLineDtosAsync(orders.SelectMany(o => o.Lines
            .Select(l => (l.Id, l.MaterialId, l.GradeId, l.Quantity, l.UnitId, l.QuantityKg))).ToList(), ct);
        return orders.Select(o =>
        {
            var lines = o.Lines.OrderBy(l => l.LineNo).Select(l => lineDtos[l.Id]).ToList();
            return new OrderDto(o.Id, o.CustomerId, o.OrderDate, o.Stage, o.OnHold, o.RepresentativeId, o.Notes,
                lines, lines.Sum(l => l.QuantityKg), o.Version, o.CreatedAt);
        }).ToList();
    }

    // ---------------- التوريدات ----------------

    public async Task<Result<SupplyDto>> CreateSupplyAsync(CreateSupplyRequest request, CancellationToken ct)
    {
        if (!user.Has(Permissions.SuppliesManage))
            return AppError.Forbidden();
        var loaded = await access.LoadEditableAsync(request.SupplierId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (!loaded.Value!.IsSupplier)
            return AppError.Validation("التوريدات تُسجل للموردين فقط");

        var existing = await db.Supplies.AsNoTracking().FirstOrDefaultAsync(s => s.Id == request.Id, ct);
        if (existing is not null)
            return existing.CreatedBy == user.UserId && existing.SupplierId == request.SupplierId
                ? await GetSupplyAsync(existing.Id, ct)
                : AppError.Conflict("supply.id_taken", "معرف التوريد مستخدم بالفعل");

        if (request.Id == Guid.Empty || !Enum.IsDefined(request.Status))
            return AppError.Validation("بيانات التوريد غير مكتملة");
        if (request.Lines.Count == 0)
            return AppError.Validation("التوريد يحتاج خامة واحدة على الأقل");
        var lines = await BuildLinesAsync(request.Lines, ct);
        if (lines.Error is not null)
            return lines.Error;

        var supply = new Supply
        {
            Id = request.Id,
            SupplierId = request.SupplierId,
            SupplyDate = request.SupplyDate,
            Status = request.Status,
            Notes = PartyService.Clean(request.Notes, 300),
        };
        supply.Stamp(user.UserId, clock.GetUtcNow());
        foreach (var (material, grade, quantity, unit, kg) in lines.Value!)
            supply.Lines.Add(new SupplyLine
            {
                LineNo = supply.Lines.Count + 1,
                MaterialId = material,
                GradeId = grade,
                Quantity = quantity,
                UnitId = unit,
                QuantityKg = kg,
            });
        db.Supplies.Add(supply);
        db.Audit(user, clock, "supply.created", "supply", supply.Id,
            new { supply.SupplierId, status = supply.Status.ToString() });
        await db.SaveChangesAsync(ct);
        return await GetSupplyAsync(supply.Id, ct);
    }

    public async Task<Result<SupplyDto>> ChangeSupplyStatusAsync(Guid supplyId, ChangeSupplyStatusRequest request, CancellationToken ct)
    {
        if (!user.Has(Permissions.SuppliesManage))
            return AppError.Forbidden();
        var supply = await db.Supplies.FirstOrDefaultAsync(s => s.Id == supplyId && s.DeletedAt == null, ct);
        if (supply is null)
            return AppError.NotFound();
        var party = await access.LoadEditableAsync(supply.SupplierId, ct);
        if (!party.IsSuccess)
            return party.Error!;
        if (supply.Version != request.Version)
            return AppError.StaleVersion();
        var allowed = supply.Status == SupplyStatus.Expected && request.Status != SupplyStatus.Expected;
        if (!Enum.IsDefined(request.Status) || !allowed)
            return AppError.Validation("لا يمكن تغيير حالة توريد مستلم أو ملغي", "supply.invalid_transition");

        db.SetOriginalVersion(supply, request.Version);
        db.Audit(user, clock, "supply.status_changed", "supply", supply.Id,
            new { from = supply.Status.ToString(), to = request.Status.ToString() });
        supply.Status = request.Status;
        supply.Touch(user.UserId, clock.GetUtcNow());
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return AppError.StaleVersion();
        }
        return await GetSupplyAsync(supply.Id, ct);
    }

    public async Task<Result<SupplyDto>> GetSupplyAsync(Guid supplyId, CancellationToken ct)
    {
        var supply = await db.Supplies.AsNoTracking().Include(s => s.Lines)
            .FirstOrDefaultAsync(s => s.Id == supplyId && s.DeletedAt == null, ct);
        if (supply is null || !(await access.LoadVisibleAsync(supply.SupplierId, ct)).IsSuccess)
            return AppError.NotFound();
        return (await ToSupplyDtosAsync([supply], ct))[0];
    }

    public async Task<Result<IReadOnlyList<SupplyDto>>> ListSuppliesAsync(Guid supplierId, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(supplierId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var supplies = await db.Supplies.AsNoTracking().Include(s => s.Lines)
            .Where(s => s.SupplierId == supplierId && s.DeletedAt == null)
            .OrderByDescending(s => s.SupplyDate).ThenByDescending(s => s.CreatedAt)
            .Take(200).ToListAsync(ct);
        return await ToSupplyDtosAsync(supplies, ct);
    }

    private async Task<List<SupplyDto>> ToSupplyDtosAsync(List<Supply> supplies, CancellationToken ct)
    {
        var lineDtos = await ToLineDtosAsync(supplies.SelectMany(s => s.Lines
            .Select(l => (l.Id, l.MaterialId, l.GradeId, l.Quantity, l.UnitId, l.QuantityKg))).ToList(), ct);
        return supplies.Select(s =>
        {
            var lines = s.Lines.OrderBy(l => l.LineNo).Select(l => lineDtos[l.Id]).ToList();
            return new SupplyDto(s.Id, s.SupplierId, s.SupplyDate, s.Status, s.Notes, lines,
                lines.Sum(l => l.QuantityKg), s.Version, s.CreatedAt);
        }).ToList();
    }

    // ---------------- مشترك ----------------

    private async Task<Result<List<(Guid Material, Guid? Grade, decimal Quantity, Guid Unit, decimal Kg)>>> BuildLinesAsync(
        IReadOnlyList<LineInput>? inputs, CancellationToken ct)
    {
        if (inputs is null || inputs.Count == 0)
            return AppError.Validation("أضف خامة واحدة على الأقل");
        if (inputs.Count > MaxLines)
            return AppError.Validation($"الحد الأقصى {MaxLines} خامة في السجل الواحد");

        var units = await db.Units.AsNoTracking().Where(u => u.IsActive).ToDictionaryAsync(u => u.Id, ct);
        var result = new List<(Guid, Guid?, decimal, Guid, decimal)>();
        foreach (var line in inputs)
        {
            if (line.Quantity <= 0 || line.Quantity > 1_000_000_000)
                return AppError.Validation("الكمية يجب أن تكون أكبر من صفر");
            if (!units.TryGetValue(line.UnitId, out var unit))
                return AppError.Validation("الوحدة غير معروفة");
            if (!await db.Materials.AnyAsync(m => m.Id == line.MaterialId && m.IsActive, ct))
                return AppError.Validation("الخامة غير معروفة");
            var grade = await reference.ResolveGradeAsync(line.MaterialId, line.GradeCode, ct);
            result.Add((line.MaterialId, grade?.Id, line.Quantity, unit.Id, unit.ToKg(line.Quantity)));
        }
        return result;
    }

    private async Task<Dictionary<Guid, LineDto>> ToLineDtosAsync(
        List<(Guid Id, Guid MaterialId, Guid? GradeId, decimal Quantity, Guid UnitId, decimal QuantityKg)> lines,
        CancellationToken ct)
    {
        var materialIds = lines.Select(l => l.MaterialId).ToHashSet();
        var gradeIds = lines.Select(l => l.GradeId).OfType<Guid>().ToHashSet();
        var unitIds = lines.Select(l => l.UnitId).ToHashSet();
        var materials = await db.Materials.AsNoTracking().Where(m => materialIds.Contains(m.Id)).ToDictionaryAsync(m => m.Id, m => m.Code, ct);
        var grades = await db.Grades.AsNoTracking().Where(g => gradeIds.Contains(g.Id)).ToDictionaryAsync(g => g.Id, g => g.Code, ct);
        var units = await db.Units.AsNoTracking().Where(u => unitIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Code, ct);
        return lines.ToDictionary(l => l.Id, l => new LineDto(l.Id, l.MaterialId, materials.GetValueOrDefault(l.MaterialId, "?"),
            l.GradeId, l.GradeId is { } g ? grades.GetValueOrDefault(g) : null, l.Quantity, l.UnitId,
            units.GetValueOrDefault(l.UnitId, "?"), l.QuantityKg));
    }

    private static bool AppliesTo(string appliesTo, Party party) =>
        appliesTo == LookupAppliesTo.Both
        || (appliesTo == LookupAppliesTo.Customer && party.IsCustomer)
        || (appliesTo == LookupAppliesTo.Supplier && party.IsSupplier);

    private static string StageName(OrderStage stage) => stage switch
    {
        OrderStage.Inquiry => "استفسار",
        OrderStage.Quotation => "عرض سعر",
        OrderStage.Confirmed => "مؤكد",
        OrderStage.InProgress => "قيد التنفيذ",
        OrderStage.Completed => "مكتمل",
        OrderStage.Cancelled => "ملغي",
        _ => stage.ToString(),
    };
}
