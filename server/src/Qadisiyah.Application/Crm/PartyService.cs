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
    MaterialSpecs specs,
    PartySummaries summaries,
    TimeProvider clock)
{
    private const int MaxPhones = 5;
    private const int MaxListItems = 50;

    public async Task<Result<CreatePartyResult>> CreateAsync(CreatePartyRequest request, CancellationToken ct)
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
            return new CreatePartyResult(existing.Id, existing.Name, false, (await GetAsync(existing.Id, ct)).Value);
        }

        var validation = ValidateCommon(request.Name, request.Email, request.Phones, requirePhone: true);
        if (validation.Error is not null)
            return validation.Error;
        var phones = validation.Value!;

        var duplicate = await DuplicateErrorAsync(phones, null, ct);
        if (duplicate is not null)
            return duplicate;
        if (!request.ConfirmSimilar)
        {
            var similar = await SimilarErrorAsync(request.Name, request.Email, phones, ct);
            if (similar is not null)
                return similar;
        }

        // المندوب العادي: المسؤول هو حسابه وتاريخ السجل اليوم، مهما أرسل الجهاز.
        var today = BusinessClock.Today(clock);
        var representativeId = access.CanAssign ? request.RepresentativeId : null;
        var recordDate = access.CanAssign && request.RecordDate is { } chosen ? chosen : today;
        if (recordDate > today)
            return AppError.Validation("تاريخ السجل لا يمكن أن يكون في المستقبل");

        var refError = await ValidateReferencesAsync(
            request.IsCustomer ? request.CustomerActivityId : null,
            request.IsSupplier ? request.SupplierActivityId : null,
            representativeId, request.GovernorateId, ct);
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
            RepresentativeId = representativeId ?? await MyRepresentativeIdAsync(ct),
            RecordDate = recordDate,
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
                var added = await AddProductInternalAsync(party, product, ct);
                if (!added.IsSuccess)
                    return added.Error!;
            }
        }

        db.Parties.Add(party);
        db.Audit(user, clock, "party.created", "party", party.Id,
            new { party.IsCustomer, party.IsSupplier });
        await db.SaveChangesAsync(ct);
        return new CreatePartyResult(party.Id, party.Name, true, (await GetAsync(party.Id, ct)).Value);
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

        var duplicate = await DuplicateErrorAsync(phones, party.Id, ct);
        if (duplicate is not null)
            return duplicate;
        if (request.RecordDate is { } newDate && newDate > BusinessClock.Today(clock))
            return AppError.Validation("تاريخ السجل لا يمكن أن يكون في المستقبل");

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
        if (request.RecordDate is { } recordDate)
        {
            Track("recordDate", party.RecordDate != recordDate);
            party.RecordDate = recordDate;
        }
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
        if (party is null || !await access.CanViewAsync(party, ct))
            return AppError.NotFound();
        // من لا يرى الموردين لا يرى جانب «المورد» لشركة يتعامل معها كعميل، والعكس لمن
        // يرى الشركة كمورد فقط (مدير المشتريات مع عميل ليس تابعًا له).
        if (!access.CanSeeSuppliers && party.IsSupplier)
        {
            party.IsSupplier = false;
            party.SupplierActivityId = null;
            party.Products.Clear();
        }
        if (party.IsCustomer && !await access.CanSeeCustomerSideAsync(party, ct))
        {
            party.IsCustomer = false;
            party.CustomerActivityId = null;
            party.Interests.Clear();
        }

        var describe = await specs.DescribeAsync(
            party.Interests.Select(ToSpec).Concat(party.Products.Select(ToSpec)), ct);
        var repName = party.RepresentativeId is { } repId
            ? await db.Representatives.Where(r => r.Id == repId).Select(r => r.Name).FirstOrDefaultAsync(ct)
            : null;

        var prices = user.Has(Permissions.PricesView)
            ? await LatestPricesAsync(party.Products.Select(p => p.Id).ToList(), ct)
            : new Dictionary<Guid, LatestPriceDto>();

        var (customerSummary, supplierSummary) = (await summaries.LoadAsync(
            [new PartySummaries.Party(party.Id, party.IsCustomer, party.IsSupplier)], ct))[party.Id];
        var isFavorite = await db.UserFavorites.AnyAsync(f => f.UserId == user.UserId && f.PartyId == id, ct);
        var logoId = await db.Attachments
            .Where(a => a.PartyId == id && a.Kind == AttachmentKind.Logo && a.DeletedAt == null)
            .OrderByDescending(a => a.CreatedAt).Select(a => (Guid?)a.Id).FirstOrDefaultAsync(ct);

        return new PartyDetail(
            party.Id, party.Version, party.Name, party.IsCustomer, party.IsSupplier,
            party.Phones.OrderByDescending(p => p.IsPrimary).ThenBy(p => p.E164)
                .Select(p => new PhoneDto(p.Id, p.E164, p.Label, p.IsPrimary, p.WhatsAppE164)).ToList(),
            party.CustomerActivityId, party.SupplierActivityId, party.RepresentativeId, repName,
            party.Email, party.Notes, party.CountryCode, party.GovernorateId, party.Region, party.AddressLine,
            party.Latitude, party.Longitude,
            party.Interests.Select(i => ToInterestDto(i, describe(ToSpec(i)))).ToList(),
            party.Products.Where(p => p.IsActive)
                .Select(p => ToProductDto(p, describe(ToSpec(p)), prices.GetValueOrDefault(p.Id))).ToList(),
            customerSummary, supplierSummary,
            access.CanManage, party.CreatedAt, party.UpdatedAt, isFavorite, logoId,
            (await access.LoadForAddAsync(party.Id, ct)).IsSuccess,
            party.RecordDate ?? DateOnly.FromDateTime(party.CreatedAt.UtcDateTime),
            await db.Users.Where(u => u.Id == party.CreatedBy).Select(u => u.DisplayName).FirstOrDefaultAsync(ct),
            party.NameMissing,
            party.PendingGradeId is { } pending
                ? await db.Grades.Where(g => g.Id == pending).Select(g => g.Code).FirstOrDefaultAsync(ct)
                : null,
            NeedsCompletion(party) && CanCompleteAny());
    }

    private static bool NeedsCompletion(Party p) => p.NameMissing || p.Phones.Count == 0 || (!p.IsCustomer && !p.IsSupplier);

    private bool CanCompleteAny() => user.Has(Permissions.CustomersCreate) || user.Has(Permissions.SuppliersCreate);

    public async Task<Result<PartyDetail>> CompleteAsync(Guid id, CompleteRequest request, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (!CanCompleteAny())
            return AppError.Forbidden();
        var party = await db.Parties.Include(p => p.Phones).Include(p => p.Interests).Include(p => p.Products)
            .FirstAsync(p => p.Id == id, ct);
        var filled = new List<string>();

        if (!string.IsNullOrWhiteSpace(request.Name))
        {
            if (!party.NameMissing)
                return AppError.Forbidden("الاسم محفوظ بالفعل. تعديله للمدير العام فقط");
            var name = request.Name.Trim();
            if (name.Length is < 2 or > 200)
                return AppError.Validation("الاسم مطلوب (من 2 إلى 200 حرف)");
            party.Name = name;
            party.NormalizedName = TextNormalizer.Normalize(name);
            party.NameMissing = false;
            filled.Add("name");
        }

        if (request.Phone is { } phoneInput)
        {
            if (party.Phones.Count > 0)
                return AppError.Forbidden("للسجل رقم محفوظ. إضافة أرقام أخرى من جهات الاتصال");
            var validation = ValidateCommon(party.Name, null, [phoneInput], requirePhone: true);
            if (validation.Error is not null)
                return validation.Error;
            var duplicate = await DuplicateErrorAsync(validation.Value!, party.Id, ct);
            if (duplicate is not null)
                return duplicate;
            foreach (var phone in validation.Value!)
            {
                phone.PartyId = party.Id;
                party.Phones.Add(phone);
                db.PartyPhones.Add(phone);
            }
            filled.Add("phone");
        }

        if (request.IsCustomer || request.IsSupplier)
        {
            if (party.IsCustomer || party.IsSupplier)
                return AppError.Forbidden("نوع السجل محدد بالفعل. إضافة دور آخر من «إضافة كعميل/كمورد»");
            if (!access.CanCreate(request.IsCustomer, request.IsSupplier))
                return AppError.Forbidden();
            party.IsCustomer = request.IsCustomer;
            party.IsSupplier = request.IsSupplier;
            if (party.PendingGradeId is { } gradeId
                && await db.Grades.Where(g => g.Id == gradeId).Select(g => (Guid?)g.MaterialId).FirstOrDefaultAsync(ct) is { } materialId)
            {
                if (party.IsCustomer)
                    db.CustomerInterests.Add(new CustomerInterest { PartyId = party.Id, MaterialId = materialId, GradeId = gradeId });
                if (party.IsSupplier)
                    db.SupplierProducts.Add(new SupplierProduct { PartyId = party.Id, MaterialId = materialId, GradeId = gradeId });
            }
            party.PendingGradeId = null;
            filled.Add("type");
        }

        if (filled.Count == 0)
            return AppError.Validation("لا توجد بيانات للاستكمال");
        party.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "party.completed", "party", party.Id, new { fields = filled });
        await db.SaveChangesAsync(ct);
        return (await GetAsync(id, ct)).Value!;
    }

    public async Task<Result<ProductDto>> AddProductAsync(Guid partyId, ProductInput input, CancellationToken ct)
    {
        var loaded = await access.LoadForAddAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (!party.IsSupplier)
            return AppError.Validation("المنتجات تُضاف للموردين فقط");

        await db.SupplierProducts.Where(p => p.PartyId == party.Id).LoadAsync(ct);
        var before = party.Products.Count;
        var added = await AddProductInternalAsync(party, input, ct);
        if (!added.IsSuccess)
            return added.Error!;
        var productId = added.Value;
        if (party.Products.Count > before)
        {
            var product = party.Products[^1];
            var label = (await specs.DescribeAsync([ToSpec(product)], ct))(ToSpec(product));
            db.Audit(user, clock, "party.product_added", "party", party.Id, new { spec = SpecLabel(label) });
        }
        party.Touch(user.UserId, clock.GetUtcNow());
        await db.SaveChangesAsync(ct);
        var detail = (await GetAsync(partyId, ct)).Value!;
        return detail.Products.First(p => p.Id == productId);
    }

    /// <summary>إضافة خامة لعميل (إضافة فقط؛ الموجود لا يتغير).</summary>
    public async Task<Result<PartyDetail>> AddInterestAsync(Guid partyId, InterestInput input, CancellationToken ct)
    {
        var loaded = await access.LoadForAddAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (!party.IsCustomer)
            return AppError.Validation("الخامات المطلوبة تُضاف للعملاء فقط");
        await db.CustomerInterests.Where(i => i.PartyId == party.Id).LoadAsync(ct);
        var before = party.Interests.Count;
        var error = await AddInterestsAsync(party, [input], ct);
        if (error is not null)
            return error;
        if (party.Interests.Count > before)
        {
            var added = party.Interests[^1];
            var label = (await specs.DescribeAsync([ToSpec(added)], ct))(ToSpec(added));
            db.Audit(user, clock, "party.interest_added", "party", party.Id, new { spec = SpecLabel(label) });
            party.Touch(user.UserId, clock.GetUtcNow());
            await db.SaveChangesAsync(ct);
        }
        return (await GetAsync(partyId, ct)).Value!;
    }

    /// <summary>
    /// إسناد السجل لمندوب آخر: للمدير العام، ولمديري الأقسام داخل نطاق اطلاعهم. حدث إداري
    /// مستقل يُسجَّل في التدقيق، ولا يمنح تعديلًا لبيانات الشركة نفسها.
    /// </summary>
    public async Task<Result<PartyDetail>> AssignAsync(Guid id, AssignRequest request, CancellationToken ct)
    {
        if (!access.CanManage && !user.Has(Permissions.TeamAssign))
            return AppError.Forbidden("الإسناد لمديري الأقسام والمدير العام فقط");
        var loaded = await access.LoadVisibleAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (party.IsCustomer && !party.IsSupplier && !await access.CanSeeCustomerSideAsync(party, ct))
            return AppError.NotFound();
        var rep = await db.Representatives.FirstOrDefaultAsync(r => r.Id == request.RepresentativeId, ct);
        if (rep is null)
            return AppError.Validation("المندوب غير معروف");
        if (party.RepresentativeId != rep.Id)
        {
            var from = party.RepresentativeId;
            party.RepresentativeId = rep.Id;
            party.Touch(user.UserId, clock.GetUtcNow());
            db.Audit(user, clock, "party.assigned", "party", party.Id, new { from, to = rep.Id, rep = rep.Name });
            await db.SaveChangesAsync(ct);
        }
        return (await GetAsync(id, ct)).Value!;
    }

    /// <summary>حذف آمن (منطقي) للمدير فقط؛ التعاملات المرتبطة تبقى كما هي.</summary>
    public async Task<Result<bool>> DeleteAsync(Guid id, CancellationToken ct)
    {
        var loaded = await access.LoadEditableAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        var now = clock.GetUtcNow();
        party.DeletedAt = now;
        party.Touch(user.UserId, now);
        db.Audit(user, clock, "party.deleted", "party", party.Id, new { party.Name });
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<Result<PartyDetail>> RestoreAsync(Guid id, CancellationToken ct)
    {
        var loaded = await access.LoadAnyForManageAsync(id, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        var party = loaded.Value!;
        if (party.DeletedAt is not null)
        {
            var phones = await db.PartyPhones.Where(p => p.PartyId == id).Select(p => p.E164).ToListAsync(ct);
            if (await FindDuplicatePhoneAsync(phones, id, ct) is { } other)
                return AppError.Conflict("party.restore_duplicate",
                    $"لا يمكن الاستعادة: رقم الهاتف مسجل الآن باسم «{other.Name}»");
            party.DeletedAt = null;
            party.Touch(user.UserId, clock.GetUtcNow());
            db.Audit(user, clock, "party.restored", "party", party.Id, new { party.Name });
            await db.SaveChangesAsync(ct);
        }
        return (await GetAsync(id, ct)).Value!;
    }

    /// <summary>
    /// تكرار رقم الهاتف. إذا كان السجل الموجود ظاهرًا للمستخدم تُعرض بياناته ليفتحه أو يضيف
    /// الدور؛ وإلا تنبيه عام دون كشف اسم أو نوع السجل المخفي.
    /// </summary>
    private static readonly string[] GenericWords =
        ["شركه", "الشركه", "مصنع", "مصانع", "مؤسسه", "مجموعه", "للصناعات", "الصناعات", "لصناعه", "co", "company", "factory"];

    /// <summary>الاسم دون الكلمات العامة (شركة، مصنع...) للمقارنة بين الأسماء المتقاربة.</summary>
    internal static string CoreName(string? name) =>
        string.Join(' ', TextNormalizer.Normalize(name).Split(' ')
            .Where(w => !GenericWords.Contains(w)).Select(w => w.StartsWith("ال", StringComparison.Ordinal) && w.Length > 4 ? w[2..] : w));

    /// <summary>
    /// مؤشرات تكرار إضافية غير الهاتف: الاسم نفسه بعد التطبيع وحذف الكلمات العامة، أو نفس البريد،
    /// أو رقم مسجل لموظف في شركة أخرى. يُطلب التأكيد؛ والسجلات غير الظاهرة لا تُكشف تفاصيلها.
    /// </summary>
    private async Task<AppError?> SimilarErrorAsync(string name, string? email, List<PartyPhone> phones, CancellationToken ct)
    {
        var core = CoreName(name);
        var normalizedEmail = string.IsNullOrWhiteSpace(email) ? null : email.Trim().ToLowerInvariant();
        var numbers = phones.Select(p => p.E164).ToList();
        var token = core.Split(' ', StringSplitOptions.RemoveEmptyEntries).OrderByDescending(w => w.Length).FirstOrDefault();

        var candidates = await db.Parties.AsNoTracking()
            .Where(p => p.DeletedAt == null && (
                (token != null && token.Length >= 3 && p.NormalizedName.Contains(token))
                || (normalizedEmail != null && p.Email != null
#pragma warning disable CA1862, CA1304, CA1311 // يُترجم إلى lower() في PostgreSQL
                    && p.Email.ToLower() == normalizedEmail)
#pragma warning restore CA1862, CA1304, CA1311
                || db.PartyContacts.Any(c => c.PartyId == p.Id && c.DeletedAt == null && c.Mobile != null
                    && numbers.Contains(c.Mobile))))
            .Take(50)
            .ToListAsync(ct);
        var contactHits = await db.PartyContacts.AsNoTracking()
            .Where(c => c.DeletedAt == null && c.Mobile != null && numbers.Contains(c.Mobile))
            .Select(c => c.PartyId).ToListAsync(ct);

        var matches = new List<(Party Party, List<string> Reasons)>();
        foreach (var p in candidates)
        {
            var reasons = new List<string>();
            if (core.Length > 0 && CoreName(p.Name) == core)
                reasons.Add("name");
            if (normalizedEmail != null && p.Email?.Trim().ToLowerInvariant() == normalizedEmail)
                reasons.Add("email");
            if (contactHits.Contains(p.Id))
                reasons.Add("contact_phone");
            if (reasons.Count > 0)
                matches.Add((p, reasons));
        }
        if (matches.Count == 0)
            return null;

        var visible = new List<SimilarParty>();
        foreach (var (p, reasons) in matches)
            if (await access.CanViewAsync(p, ct))
                visible.Add(new SimilarParty(p.Id, p.Name, p.IsCustomer, p.IsSupplier && access.CanSeeSuppliers, reasons));
        return visible.Count > 0
            ? AppError.Conflict("party.similar", "يوجد سجل مشابه. تأكد أنه ليس نفس الشركة قبل الحفظ", visible)
            : AppError.Conflict("party.similar_hidden",
                "توجد شركة مشابهة مسجلة في النظام. تأكد من البيانات أو تواصل مع الإدارة قبل الحفظ");
    }

    private async Task<AppError?> DuplicateErrorAsync(List<PartyPhone> phones, Guid? exceptId, CancellationToken ct)
    {
        var duplicate = await FindDuplicatePhoneAsync(phones.Select(p => p.E164), exceptId, ct);
        if (duplicate is null)
            return null;
        var existing = await db.Parties.AsNoTracking().FirstAsync(p => p.Id == duplicate.PartyId, ct);
        return await access.CanViewAsync(existing, ct)
            ? AppError.Conflict("party.duplicate_phone", $"رقم الهاتف مسجل بالفعل باسم «{duplicate.Name}»",
                access.CanSeeSuppliers ? duplicate : duplicate with { IsSupplier = false })
            : AppError.Conflict("party.duplicate_phone_hidden",
                "رقم الهاتف مسجل بالفعل في النظام. إذا كان العميل تابعًا لك تواصل مع الإدارة.");
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
        foreach (var interest in interests)
        {
            if (interest.UnitId is { } unitId && !await db.Units.AnyAsync(u => u.Id == unitId, ct))
                return AppError.Validation("وحدة غير معروفة");
            if (interest.MonthlyQuantity is < 0)
                return AppError.Validation("الكمية لا يمكن أن تكون سالبة");
            var spec = await specs.ResolveAsync(interest.Spec, allowOpen: true, ct);
            if (!spec.IsSuccess)
                return spec.Error;
            if (party.Interests.Any(i => ToSpec(i) == spec.Value))
                continue;
            // يُضاف صراحة: المعرف مولد مسبقًا فلا يُفترض أنه سجل موجود عند إضافته لعميل محفوظ.
            var added = new CustomerInterest
            {
                PartyId = party.Id,
                MaterialId = spec.Value!.MaterialId,
                GradeId = spec.Value.GradeId,
                OriginCountryId = spec.Value.OriginCountryId,
                OpenSpec = spec.Value.OpenSpec,
                MonthlyQuantity = interest.MonthlyQuantity,
                UnitId = interest.UnitId,
            };
            party.Interests.Add(added);
            db.CustomerInterests.Add(added);
        }
        return null;
    }

    /// <summary>يضيف منتجًا للمورد أو يعيد المنتج الموجود بنفس المواصفات.</summary>
    private async Task<Result<Guid>> AddProductInternalAsync(Party party, ProductInput input, CancellationToken ct)
    {
        var spec = await specs.ResolveAsync(input.Spec, allowOpen: false, ct);
        if (!spec.IsSuccess)
            return spec.Error!;
        var existing = party.Products.FirstOrDefault(p => p.IsActive && ToSpec(p) == spec.Value);
        if (existing is not null)
            return existing.Id;
        var product = new SupplierProduct
        {
            PartyId = party.Id,
            MaterialId = spec.Value!.MaterialId,
            GradeId = spec.Value.GradeId,
            OriginCountryId = spec.Value.OriginCountryId,
            Notes = Clean(input.Notes, 500),
        };
        party.Products.Add(product);
        db.SupplierProducts.Add(product);
        return product.Id;
    }

    internal static string SpecLabel(SpecInfo s) => string.Join(" · ", new[]
    {
        s.MaterialCode,
        s.OpenSpec ? "أي شركة" : s.ManufacturerName,
        s.GradeCode,
        s.OriginName,
    }.Where(x => !string.IsNullOrEmpty(x)));

    private static InterestDto ToInterestDto(CustomerInterest i, SpecInfo spec) =>
        new(i.Id, i.MaterialId, spec.MaterialCode, i.GradeId, spec.GradeCode, i.MonthlyQuantity, i.UnitId, spec);

    private static ProductDto ToProductDto(SupplierProduct p, SpecInfo spec, LatestPriceDto? price) =>
        new(p.Id, p.MaterialId, spec.MaterialCode, p.GradeId, spec.GradeCode, p.Notes, price, spec);

    private static ResolvedSpec ToSpec(CustomerInterest i) => new(i.MaterialId, i.GradeId, i.OriginCountryId, i.OpenSpec);

    private static ResolvedSpec ToSpec(SupplierProduct p) => new(p.MaterialId, p.GradeId, p.OriginCountryId, false);

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
}
