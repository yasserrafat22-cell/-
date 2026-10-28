using System.Globalization;
using System.Net.Mail;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Application.Reference;
using Qadisiyah.Domain.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Identity;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Crm;

/// <summary>تسجيل العملاء والموردين وملفاتهم ومنتجات الموردين وعروض أسعارهم.</summary>
public sealed class PartyService(
    IAppDbContext db,
    ICurrentUser user,
    PartyAccess access,
    ReferenceService reference,
    TimeProvider clock)
{
    private const int MaxPhones = 5;
    private const int MaxListItems = 50;

    public async Task<Result<(PartyDetail Party, bool Created)>> CreateAsync(CreatePartyRequest request, CancellationToken ct)
    {
        if (request.Id == Guid.Empty)
            return AppError.Validation("معرف السجل مطلوب");
        if (!access.CanCreate(request.IsCustomer, request.IsSupplier))
            return request.IsCustomer || request.IsSupplier
                ? AppError.Forbidden()
                : AppError.Validation("حدد نوع التسجيل: عميل أو مورد");

        // إعادة إرسال نفس الطلب (مثلًا بعد انقطاع الاتصال) تعيد السجل نفسه.
        var existing = await db.Parties.AsNoTracking().FirstOrDefaultAsync(p => p.Id == request.Id, ct);
        if (existing is not null)
        {
            if (existing.CreatedBy != user.UserId)
                return AppError.Conflict("party.id_taken", "معرف السجل مستخدم بالفعل");
            return (await GetAsync(existing.Id, ct)).Value is { } same
                ? (same, false)
                : AppError.NotFound();
        }

        var validation = ValidateCommon(request.Name, request.Email, request.Phones, requirePhone: true);
        if (validation.Error is not null)
            return validation.Error;
        var phones = validation.Value!;

        var duplicate = await FindDuplicatePhoneAsync(phones.Select(p => p.E164), null, ct);
        if (duplicate is not null)
            return AppError.Conflict("party.duplicate_phone",
                $"رقم الهاتف مسجل بالفعل باسم «{duplicate.Name}»", duplicate);

        var refError = await ValidateReferencesAsync(
            request.IsCustomer ? request.CustomerActivityId : null,
            request.IsSupplier ? request.SupplierActivityId : null,
            request.RepresentativeId, request.GovernorateId, ct);
        if (refError is not null)
            return refError;

        var now = clock.GetUtcNow();
        var party = new Party
        {
            Id = request.Id,
            Name = request.Name.Trim(),
            NormalizedName = TextNormalizer.Normalize(request.Name),
            IsCustomer = request.IsCustomer,
            IsSupplier = request.IsSupplier,
            CustomerActivityId = request.IsCustomer ? request.CustomerActivityId : null,
            SupplierActivityId = request.IsSupplier ? request.SupplierActivityId : null,
            RepresentativeId = request.RepresentativeId ?? await MyRepresentativeIdAsync(ct),
        };
        party.Stamp(user.UserId, now);
        ApplyDetails(party, request.Email, request.Notes, request.GovernorateId, request.Region, request.AddressLine,
            request.Latitude, request.Longitude);
        party.Phones.AddRange(phones);

        if (request.IsCustomer && request.Interests is { Count: > 0 } interests)
        {
            var error = await AddInterestsAsync(party, interests, ct);
            if (error is not null)
                return error;
        }
        if (request.IsSupplier && request.Products is { Count: > 0 } products)
        {
            foreach (var product in products)
            {
                var error = await AddProductInternalAsync(party, product, ct);
                if (error is not null)
                    return error;
            }
        }

        db.Parties.Add(party);
        db.Audit(user, clock, "party.created", "party", party.Id,
            new { party.IsCustomer, party.IsSupplier });
        await db.SaveChangesAsync(ct);
        return ((await GetAsync(party.Id, ct)).Value!, true);
    }

    public async Task<Result<PartyDetail>> UpdateAsync(Guid id, UpdatePartyRequest request, CancellationToken ct)
    {
        var loaded = await access.LoadEditableAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (party.Version != request.Version)
            return AppError.StaleVersion();

        var validation = ValidateCommon(request.Name, request.Email, request.Phones, requirePhone: true);
        if (validation.Error is not null)
            return validation.Error;
        var phones = validation.Value!;

        var duplicate = await FindDuplicatePhoneAsync(phones.Select(p => p.E164), party.Id, ct);
        if (duplicate is not null)
            return AppError.Conflict("party.duplicate_phone",
                $"رقم الهاتف مسجل بالفعل باسم «{duplicate.Name}»", duplicate);

        var refError = await ValidateReferencesAsync(
            party.IsCustomer ? request.CustomerActivityId : null,
            party.IsSupplier ? request.SupplierActivityId : null,
            request.RepresentativeId, request.GovernorateId, ct);
        if (refError is not null)
            return refError;

        await db.PartyPhones.Where(p => p.PartyId == party.Id).LoadAsync(ct);
        await db.CustomerInterests.Where(i => i.PartyId == party.Id).LoadAsync(ct);
        db.SetOriginalVersion(party, request.Version);

        var changes = new List<string>();
        void Track(string field, bool changed)
        {
            if (changed)
                changes.Add(field);
        }

        Track("name", party.Name != request.Name.Trim());
        party.Name = request.Name.Trim();
        party.NormalizedName = TextNormalizer.Normalize(request.Name);
        if (party.IsCustomer)
        {
            Track("customerActivity", party.CustomerActivityId != request.CustomerActivityId);
            party.CustomerActivityId = request.CustomerActivityId;
        }
        if (party.IsSupplier)
        {
            Track("supplierActivity", party.SupplierActivityId != request.SupplierActivityId);
            party.SupplierActivityId = request.SupplierActivityId;
        }
        Track("representative", party.RepresentativeId != request.RepresentativeId);
        party.RepresentativeId = request.RepresentativeId;
        Track("details", party.Email != request.Email || party.Notes != request.Notes
            || party.GovernorateId != request.GovernorateId || party.Region != request.Region
            || party.AddressLine != request.AddressLine || party.Latitude != request.Latitude
            || party.Longitude != request.Longitude);
        ApplyDetails(party, request.Email, request.Notes, request.GovernorateId, request.Region, request.AddressLine,
            request.Latitude, request.Longitude);

        var oldPhones = party.Phones.Select(p => p.E164).Order().ToArray();
        Track("phones", !oldPhones.SequenceEqual(phones.Select(p => p.E164).Order()));
        db.PartyPhones.RemoveRange(party.Phones);
        party.Phones.Clear();
        foreach (var phone in phones)
        {
            phone.PartyId = party.Id;
            party.Phones.Add(phone);
            db.PartyPhones.Add(phone);
        }

        if (party.IsCustomer && request.Interests is not null)
        {
            Track("interests", true);
            db.CustomerInterests.RemoveRange(party.Interests);
            party.Interests.Clear();
            var error = await AddInterestsAsync(party, request.Interests, ct);
            if (error is not null)
                return error;
        }

        party.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "party.updated", "party", party.Id, new { fields = changes });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return AppError.StaleVersion();
        }
        return (await GetAsync(party.Id, ct)).Value!;
    }

    public async Task<Result<PartyDetail>> AddRoleAsync(Guid id, AddRoleRequest request, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        var addCustomer = request.IsCustomer && !party.IsCustomer;
        var addSupplier = request.IsSupplier && !party.IsSupplier;
        if (!addCustomer && !addSupplier)
            return (await GetAsync(id, ct)).Value!;
        if (!access.CanCreate(addCustomer, addSupplier))
            return AppError.Forbidden();

        var refError = await ValidateReferencesAsync(
            addCustomer ? request.CustomerActivityId : null,
            addSupplier ? request.SupplierActivityId : null, null, null, ct);
        if (refError is not null)
            return refError;

        if (addCustomer)
        {
            party.IsCustomer = true;
            party.CustomerActivityId = request.CustomerActivityId;
        }
        if (addSupplier)
        {
            party.IsSupplier = true;
            party.SupplierActivityId = request.SupplierActivityId;
        }
        party.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "party.role_added", "party", party.Id, new { addCustomer, addSupplier });
        await db.SaveChangesAsync(ct);
        return (await GetAsync(id, ct)).Value!;
    }

    public async Task<Result<PartyDetail>> GetAsync(Guid id, CancellationToken ct)
    {
        var party = await db.Parties.AsNoTracking()
            .Include(p => p.Phones).Include(p => p.Interests).Include(p => p.Products)
            .FirstOrDefaultAsync(p => p.Id == id && p.DeletedAt == null, ct);
        if (party is null || !access.CanView(party))
            return AppError.NotFound();

        var materialIds = party.Interests.Select(i => i.MaterialId).Concat(party.Products.Select(p => p.MaterialId)).ToHashSet();
        var gradeIds = party.Interests.Select(i => i.GradeId).Concat(party.Products.Select(p => p.GradeId))
            .OfType<Guid>().ToHashSet();
        var materials = await db.Materials.AsNoTracking().Where(m => materialIds.Contains(m.Id))
            .ToDictionaryAsync(m => m.Id, m => m.Code, ct);
        var grades = await db.Grades.AsNoTracking().Where(g => gradeIds.Contains(g.Id))
            .ToDictionaryAsync(g => g.Id, g => g.Code, ct);
        var repName = party.RepresentativeId is { } repId
            ? await db.Representatives.Where(r => r.Id == repId).Select(r => r.Name).FirstOrDefaultAsync(ct)
            : null;

        var prices = user.Has(Permissions.PricesView)
            ? await LatestPricesAsync(party.Products.Select(p => p.Id).ToList(), ct)
            : new Dictionary<Guid, LatestPriceDto>();

        var rules = await LoadStatusRulesAsync(ct);
        var interactions = await db.Interactions.AsNoTracking()
            .Where(i => i.PartyId == id && i.DeletedAt == null)
            .Select(i => new { i.OccurredAt, i.NextFollowUpAt, i.FollowUpDone })
            .ToListAsync(ct);
        var now = clock.GetUtcNow();
        var lastContact = interactions.Count == 0 ? (DateTimeOffset?)null : interactions.Max(i => i.OccurredAt);
        var openFollowUps = interactions.Where(i => i.NextFollowUpAt is not null && !i.FollowUpDone)
            .Select(i => i.NextFollowUpAt!.Value).ToList();
        var dueFollowUp = openFollowUps.Any(f => f <= now);
        var nextFollowUp = openFollowUps.Count == 0 ? (DateTimeOffset?)null : openFollowUps.Min();
        var today = DateOnly.FromDateTime(now.UtcDateTime);

        PartySummary? customerSummary = null;
        if (party.IsCustomer)
        {
            var orders = await db.Orders.AsNoTracking()
                .Where(o => o.CustomerId == id && o.DeletedAt == null
                    && (o.Stage == OrderStage.Confirmed || o.Stage == OrderStage.InProgress || o.Stage == OrderStage.Completed))
                .OrderByDescending(o => o.OrderDate).ThenByDescending(o => o.CreatedAt)
                .Select(o => new { o.OrderDate, Kg = o.Lines.Sum(l => l.QuantityKg) })
                .ToListAsync(ct);
            customerSummary = new PartySummary(
                PartyStatusCalculator.Calculate(orders.Select(o => o.OrderDate).ToList(), dueFollowUp, today, rules),
                orders.FirstOrDefault()?.OrderDate, orders.FirstOrDefault()?.Kg, lastContact, nextFollowUp);
        }

        PartySummary? supplierSummary = null;
        if (party.IsSupplier)
        {
            var supplies = await db.Supplies.AsNoTracking()
                .Where(s => s.SupplierId == id && s.DeletedAt == null && s.Status == SupplyStatus.Received)
                .OrderByDescending(s => s.SupplyDate).ThenByDescending(s => s.CreatedAt)
                .Select(s => new { s.SupplyDate, Kg = s.Lines.Sum(l => l.QuantityKg) })
                .ToListAsync(ct);
            supplierSummary = new PartySummary(
                PartyStatusCalculator.Calculate(supplies.Select(s => s.SupplyDate).ToList(), dueFollowUp, today, rules),
                supplies.FirstOrDefault()?.SupplyDate, supplies.FirstOrDefault()?.Kg, lastContact, nextFollowUp);
        }

        return new PartyDetail(
            party.Id, party.Version, party.Name, party.IsCustomer, party.IsSupplier,
            party.Phones.OrderByDescending(p => p.IsPrimary).ThenBy(p => p.E164)
                .Select(p => new PhoneDto(p.Id, p.E164, p.Label, p.IsPrimary, p.WhatsAppE164)).ToList(),
            party.CustomerActivityId, party.SupplierActivityId, party.RepresentativeId, repName,
            party.Email, party.Notes, party.CountryCode, party.GovernorateId, party.Region, party.AddressLine,
            party.Latitude, party.Longitude,
            party.Interests.Select(i => new InterestDto(i.Id, i.MaterialId, materials.GetValueOrDefault(i.MaterialId, "?"),
                i.GradeId, i.GradeId is { } g ? grades.GetValueOrDefault(g) : null, i.MonthlyQuantity, i.UnitId)).ToList(),
            party.Products.Where(p => p.IsActive).Select(p => new ProductDto(p.Id, p.MaterialId,
                materials.GetValueOrDefault(p.MaterialId, "?"), p.GradeId,
                p.GradeId is { } g ? grades.GetValueOrDefault(g) : null, p.Notes,
                prices.GetValueOrDefault(p.Id))).ToList(),
            customerSummary, supplierSummary,
            await access.CanEditAsync(party, ct), party.CreatedAt);
    }

    public async Task<PagedResult<PartyListItem>> ListAsync(string? role, string? query, int skip, int take, CancellationToken ct)
    {
        var customers = user.Has(Permissions.CustomersView) && role is null or "customer";
        var suppliers = user.Has(Permissions.SuppliersView) && role is null or "supplier";
        var parties = db.Parties.AsNoTracking()
            .Where(p => p.DeletedAt == null && ((customers && p.IsCustomer) || (suppliers && p.IsSupplier)));

        if (!string.IsNullOrWhiteSpace(query))
        {
            var normalized = TextNormalizer.Normalize(query);
            var phone = PhoneNumber.Normalize(query);
            parties = parties.Where(p => p.NormalizedName.Contains(normalized)
                || (phone != null && p.Phones.Any(ph => ph.E164 == phone)));
        }

        var total = await parties.CountAsync(ct);
        var items = await parties
            .OrderByDescending(p => p.UpdatedAt)
            .Skip(Math.Max(skip, 0)).Take(Math.Clamp(take, 1, MaxListItems))
            .Select(p => new PartyListItem(p.Id, p.Name, p.IsCustomer, p.IsSupplier,
                p.Phones.OrderByDescending(ph => ph.IsPrimary).Select(ph => ph.E164).FirstOrDefault(),
                db.Representatives.Where(r => r.Id == p.RepresentativeId).Select(r => r.Name).FirstOrDefault()))
            .ToListAsync(ct);
        return new PagedResult<PartyListItem>(items, total);
    }

    public async Task<Result<ProductDto>> AddProductAsync(Guid partyId, ProductInput input, CancellationToken ct)
    {
        var loaded = await access.LoadEditableAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (!party.IsSupplier)
            return AppError.Validation("المنتجات تُضاف للموردين فقط");

        await db.SupplierProducts.Where(p => p.PartyId == party.Id).LoadAsync(ct);
        var error = await AddProductInternalAsync(party, input, ct);
        if (error is not null)
            return error;
        party.Touch(user.UserId, clock.GetUtcNow());
        await db.SaveChangesAsync(ct);
        var detail = (await GetAsync(partyId, ct)).Value!;
        return detail.Products.First(p => p.MaterialId == input.MaterialId
            && string.Equals(TextNormalizer.NormalizeCode(p.GradeCode), TextNormalizer.NormalizeCode(input.GradeCode),
                StringComparison.Ordinal));
    }

    public async Task<Result<QuoteDto>> AddQuoteAsync(Guid productId, CreateQuoteRequest request, CancellationToken ct)
    {
        if (!user.Has(Permissions.PricesManage))
            return AppError.Forbidden();
        var product = await db.SupplierProducts.FirstOrDefaultAsync(p => p.Id == productId, ct);
        if (product is null || !(await access.LoadVisibleAsync(product.PartyId, ct)).IsSuccess)
            return AppError.NotFound();

        var existing = await db.PriceQuotes.AsNoTracking().FirstOrDefaultAsync(q => q.Id == request.Id, ct);
        if (existing is not null)
            return existing.CreatedBy == user.UserId && existing.SupplierProductId == productId
                ? await ToQuoteDtoAsync(existing, ct)
                : AppError.Conflict("quote.id_taken", "معرف العرض مستخدم بالفعل");

        if (request.Id == Guid.Empty || request.Price <= 0)
            return AppError.Validation("السعر يجب أن يكون أكبر من صفر");
        if (request.ValidUntil is { } until && until < request.QuoteDate)
            return AppError.Validation("تاريخ الصلاحية يجب أن يكون بعد تاريخ العرض");
        var currency = request.Currency?.Trim().ToUpperInvariant() ?? "";
        if (!await db.LookupItems.AnyAsync(l => l.Category == LookupCategories.Currency && l.Code == currency && l.IsActive, ct))
            return AppError.Validation("العملة غير معروفة");
        if (!await db.Units.AnyAsync(u => u.Id == request.UnitId && u.IsActive, ct))
            return AppError.Validation("وحدة السعر غير معروفة");

        var quote = new PriceQuote
        {
            Id = request.Id,
            SupplierProductId = productId,
            Price = request.Price,
            Currency = currency,
            UnitId = request.UnitId,
            QuoteDate = request.QuoteDate,
            ValidUntil = request.ValidUntil,
            TransportNote = Clean(request.TransportNote, 500),
            TaxNote = Clean(request.TaxNote, 500),
            Notes = Clean(request.Notes, 1000),
            CreatedAt = clock.GetUtcNow(),
            CreatedBy = user.UserId,
        };
        db.PriceQuotes.Add(quote);
        db.Audit(user, clock, "price.quote_added", "supplier_product", productId,
            new { quote.Id, quote.Price, quote.Currency, quote.QuoteDate });
        await db.SaveChangesAsync(ct);
        return await ToQuoteDtoAsync(quote, ct);
    }

    public async Task<Result<IReadOnlyList<QuoteDto>>> ListQuotesAsync(Guid productId, CancellationToken ct)
    {
        if (!user.Has(Permissions.PricesView))
            return AppError.Forbidden();
        var product = await db.SupplierProducts.AsNoTracking().FirstOrDefaultAsync(p => p.Id == productId, ct);
        if (product is null || !(await access.LoadVisibleAsync(product.PartyId, ct)).IsSuccess)
            return AppError.NotFound();

        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var quotes = await (
            from q in db.PriceQuotes.AsNoTracking()
            join u in db.Units.AsNoTracking() on q.UnitId equals u.Id
            where q.SupplierProductId == productId
            orderby q.QuoteDate descending, q.CreatedAt descending
            select new QuoteDto(q.Id, q.Price, q.Currency, q.UnitId, u.Code, q.QuoteDate, q.ValidUntil,
                q.ValidUntil != null && q.ValidUntil < today, q.TransportNote, q.TaxNote, q.Notes, q.CreatedAt))
            .ToListAsync(ct);
        return quotes;
    }

    private async Task<QuoteDto> ToQuoteDtoAsync(PriceQuote q, CancellationToken ct)
    {
        var unitCode = await db.Units.Where(u => u.Id == q.UnitId).Select(u => u.Code).FirstAsync(ct);
        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        return new QuoteDto(q.Id, q.Price, q.Currency, q.UnitId, unitCode, q.QuoteDate, q.ValidUntil,
            q.ValidUntil < today, q.TransportNote, q.TaxNote, q.Notes, q.CreatedAt);
    }

    private async Task<Dictionary<Guid, LatestPriceDto>> LatestPricesAsync(List<Guid> productIds, CancellationToken ct)
    {
        if (productIds.Count == 0)
            return [];
        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var quotes = await (
            from q in db.PriceQuotes.AsNoTracking()
            join u in db.Units.AsNoTracking() on q.UnitId equals u.Id
            where productIds.Contains(q.SupplierProductId)
            select new { q.Id, q.SupplierProductId, q.Price, q.Currency, u.Code, q.QuoteDate, q.ValidUntil, q.CreatedAt })
            .ToListAsync(ct);
        return quotes
            .GroupBy(q => q.SupplierProductId)
            .ToDictionary(g => g.Key, g =>
            {
                var q = g.OrderByDescending(x => x.QuoteDate).ThenByDescending(x => x.CreatedAt).First();
                return new LatestPriceDto(q.Id, q.Price, q.Currency, q.Code, q.QuoteDate, q.ValidUntil,
                    q.ValidUntil < today);
            });
    }

    private async Task<AppError?> AddInterestsAsync(Party party, IReadOnlyList<InterestInput> interests, CancellationToken ct)
    {
        foreach (var interest in interests.DistinctBy(i => (i.MaterialId, TextNormalizer.NormalizeCode(i.GradeCode))))
        {
            if (!await db.Materials.AnyAsync(m => m.Id == interest.MaterialId && m.IsActive, ct))
                return AppError.Validation("خامة غير معروفة");
            if (interest.UnitId is { } unitId && !await db.Units.AnyAsync(u => u.Id == unitId, ct))
                return AppError.Validation("وحدة غير معروفة");
            if (interest.MonthlyQuantity is < 0)
                return AppError.Validation("الكمية لا يمكن أن تكون سالبة");
            var grade = await reference.ResolveGradeAsync(interest.MaterialId, interest.GradeCode, ct);
            var entity = new CustomerInterest
            {
                PartyId = party.Id,
                MaterialId = interest.MaterialId,
                GradeId = grade?.Id,
                MonthlyQuantity = interest.MonthlyQuantity,
                UnitId = interest.UnitId,
            };
            party.Interests.Add(entity);
        }
        return null;
    }

    private async Task<AppError?> AddProductInternalAsync(Party party, ProductInput input, CancellationToken ct)
    {
        if (!await db.Materials.AnyAsync(m => m.Id == input.MaterialId && m.IsActive, ct))
            return AppError.Validation("خامة غير معروفة");
        var grade = await reference.ResolveGradeAsync(input.MaterialId, input.GradeCode, ct);
        if (party.Products.Any(p => p.MaterialId == input.MaterialId && p.GradeId == grade?.Id))
            return null;
        var product = new SupplierProduct
        {
            PartyId = party.Id,
            MaterialId = input.MaterialId,
            GradeId = grade?.Id,
            Notes = Clean(input.Notes, 500),
        };
        party.Products.Add(product);
        return null;
    }

    private static Result<List<PartyPhone>> ValidateCommon(string? name, string? email,
        IReadOnlyList<PhoneInput>? phones, bool requirePhone)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Trim().Length is < 2 or > 200)
            return AppError.Validation("الاسم مطلوب (من 2 إلى 200 حرف)");
        if (!string.IsNullOrWhiteSpace(email) && !MailAddress.TryCreate(email.Trim(), out _))
            return AppError.Validation("البريد الإلكتروني غير صحيح");
        if (requirePhone && (phones is null || phones.Count == 0))
            return AppError.Validation("رقم الهاتف مطلوب");
        if (phones!.Count > MaxPhones)
            return AppError.Validation($"الحد الأقصى {MaxPhones} أرقام");

        var result = new List<PartyPhone>();
        foreach (var (input, index) in phones.Select((p, i) => (p, i)))
        {
            var e164 = PhoneNumber.Normalize(input.Number);
            if (e164 is null)
                return AppError.Validation($"رقم الهاتف غير صحيح: {input.Number}", "party.invalid_phone");
            string? whatsapp = null;
            if (!string.IsNullOrWhiteSpace(input.WhatsApp))
            {
                whatsapp = PhoneNumber.Normalize(input.WhatsApp);
                if (whatsapp is null)
                    return AppError.Validation($"رقم واتساب غير صحيح: {input.WhatsApp}", "party.invalid_phone");
            }
            if (result.Any(p => p.E164 == e164))
                continue;
            result.Add(new PartyPhone
            {
                E164 = e164,
                Label = Clean(input.Label, 50),
                IsPrimary = index == 0,
                WhatsAppE164 = whatsapp == e164 ? null : whatsapp,
            });
        }
        return result;
    }

    private async Task<DuplicatePartyInfo?> FindDuplicatePhoneAsync(IEnumerable<string> phones, Guid? exceptPartyId, CancellationToken ct)
    {
        var list = phones.ToList();
        return await (
            from ph in db.PartyPhones.AsNoTracking()
            join p in db.Parties.AsNoTracking() on ph.PartyId equals p.Id
            where list.Contains(ph.E164) && p.DeletedAt == null && p.Id != exceptPartyId
            select new DuplicatePartyInfo(p.Id, p.Name, p.IsCustomer, p.IsSupplier, ph.E164))
            .FirstOrDefaultAsync(ct);
    }

    private async Task<AppError?> ValidateReferencesAsync(Guid? customerActivity, Guid? supplierActivity,
        Guid? representativeId, Guid? governorateId, CancellationToken ct)
    {
        async Task<bool> LookupOk(Guid? id, string category) =>
            id is null || await db.LookupItems.AnyAsync(l => l.Id == id && l.Category == category && l.IsActive, ct);

        if (!await LookupOk(customerActivity, LookupCategories.ActivityType)
            || !await LookupOk(supplierActivity, LookupCategories.ActivityType))
            return AppError.Validation("نوع النشاط غير معروف");
        if (!await LookupOk(governorateId, LookupCategories.Governorate))
            return AppError.Validation("المحافظة غير معروفة");
        if (representativeId is { } rep && !await db.Representatives.AnyAsync(r => r.Id == rep && r.IsActive, ct))
            return AppError.Validation("المندوب غير معروف");
        return null;
    }

    private Task<Guid?> MyRepresentativeIdAsync(CancellationToken ct) => reference.EnsureMyRepresentativeAsync(ct);

    private static void ApplyDetails(Party party, string? email, string? notes, Guid? governorateId, string? region,
        string? addressLine, double? latitude, double? longitude)
    {
        party.Email = Clean(email, 200);
        party.Notes = Clean(notes, 500);
        party.GovernorateId = governorateId;
        party.Region = Clean(region, 100);
        party.AddressLine = Clean(addressLine, 300);
        party.Latitude = latitude is >= -90 and <= 90 ? latitude : null;
        party.Longitude = longitude is >= -180 and <= 180 ? longitude : null;
    }

    internal static string? Clean(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
            return null;
        var trimmed = value.Trim();
        return trimmed.Length <= maxLength ? trimmed : trimmed[..maxLength];
    }

    internal async Task<StatusRules> LoadStatusRulesAsync(CancellationToken ct)
    {
        var settings = await db.AppSettings.AsNoTracking()
            .Where(s => s.Key.StartsWith("status."))
            .ToDictionaryAsync(s => s.Key, s => s.Value, ct);
        var defaults = new StatusRules();
        int Int(string key, int fallback) =>
            settings.TryGetValue(key, out var v) && int.TryParse(v, CultureInfo.InvariantCulture, out var i) && i > 0 ? i : fallback;
        decimal Dec(string key, decimal fallback) =>
            settings.TryGetValue(key, out var v) && decimal.TryParse(v, CultureInfo.InvariantCulture, out var d) && d > 0 ? d : fallback;
        return new StatusRules(
            Int(StatusRules.ActiveDaysKey, defaults.ActiveDays),
            Int(StatusRules.StoppedDaysKey, defaults.StoppedDays),
            Dec(StatusRules.OverdueFactorKey, defaults.OverdueFactor));
    }
}
