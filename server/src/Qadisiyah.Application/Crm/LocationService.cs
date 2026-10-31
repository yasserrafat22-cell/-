using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Qadisiyah.Application.Common;
using Qadisiyah.Domain.Crm;
using Qadisiyah.Domain.Reference;

namespace Qadisiyah.Application.Crm;

/// <summary>موقع جديد أو تعديل موقع. المعرف يولده التطبيق (إعادة الإرسال لا تكرر).</summary>
public sealed record LocationInput(
    Guid Id,
    LocationKind Kind,
    string? Label = null,
    string? AddressLine = null,
    string? MapsUrl = null,
    double? Latitude = null,
    double? Longitude = null,
    string? AccessNotes = null,
    bool IsDefault = false,
    uint Version = 0,
    Guid? GovernorateId = null,
    string? Region = null);

public sealed record LocationDto(
    Guid Id,
    Guid PartyId,
    LocationKind Kind,
    string? Label,
    string? AddressLine,
    string? MapsUrl,
    double? Latitude,
    double? Longitude,
    string? AccessNotes,
    bool IsDefault,
    uint Version,
    Guid? GovernorateId = null,
    string? Region = null);

/// <summary>مواقع العميل أو المورد (مقر، مصنع، مخزن، تحميل، تسليم...).</summary>
public sealed partial class LocationService(IAppDbContext db, ICurrentUser user, PartyAccess access, TimeProvider clock)
{
    private const int MaxLocations = 30;

    [GeneratedRegex(@"(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$")]
    private static partial Regex GoogleHost();

    /// <summary>روابط Google Maps فقط (ومنها المختصرة)، حتى لا تُحفظ روابط غير معروفة.</summary>
    public static bool IsMapsUrl(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri)
        && uri.Scheme is "https" or "http"
        && (uri.Host is "goo.gl" or "maps.app.goo.gl" or "g.co" || GoogleHost().IsMatch(uri.Host));

    public async Task<Result<IReadOnlyList<LocationDto>>> ListAsync(Guid partyId, CancellationToken ct)
    {
        var loaded = await access.LoadVisibleAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        return await db.PartyLocations.AsNoTracking()
            .Where(l => l.PartyId == partyId && l.DeletedAt == null)
            .OrderByDescending(l => l.IsDefault).ThenBy(l => l.CreatedAt)
            .Select(l => ToDto(l))
            .ToListAsync(ct);
    }

    public async Task<Result<LocationDto>> CreateAsync(Guid partyId, LocationInput input, CancellationToken ct)
    {
        var loaded = await access.LoadForAddAsync(partyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;

        var existing = await db.PartyLocations.AsNoTracking().FirstOrDefaultAsync(l => l.Id == input.Id, ct);
        if (existing is not null)
            return existing.PartyId == partyId && existing.CreatedBy == user.UserId
                ? ToDto(existing)
                : AppError.Conflict("location.id_taken", "معرف الموقع مستخدم بالفعل");

        var error = Validate(input) ?? await GovernorateErrorAsync(input.GovernorateId, ct);
        if (error is not null)
            return error;
        var count = await db.PartyLocations.CountAsync(l => l.PartyId == partyId && l.DeletedAt == null, ct);
        if (count >= MaxLocations)
            return AppError.Validation($"الحد الأقصى {MaxLocations} موقعًا");

        var location = new PartyLocation { Id = input.Id, PartyId = partyId };
        Apply(location, input);
        // أول موقع يصبح الافتراضي تلقائيًا. تغيير الافتراضي القائم تعديل لبيانات محفوظة (للمدير).
        location.IsDefault = count == 0 || (input.IsDefault && access.CanManage);
        location.Stamp(user.UserId, clock.GetUtcNow());
        if (location.IsDefault)
            await ClearDefaultAsync(partyId, ct);
        db.PartyLocations.Add(location);
        db.Audit(user, clock, "party.location_added", "party", partyId, new { label = Describe(location) });
        await db.SaveChangesAsync(ct);
        return ToDto(location);
    }

    public async Task<Result<LocationDto>> UpdateAsync(Guid id, LocationInput input, CancellationToken ct)
    {
        var location = await db.PartyLocations.FirstOrDefaultAsync(l => l.Id == id && l.DeletedAt == null, ct);
        if (location is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(location.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (location.Version != input.Version)
            return AppError.StaleVersion();
        var error = Validate(input) ?? await GovernorateErrorAsync(input.GovernorateId, ct);
        if (error is not null)
            return error;

        if (input.IsDefault && !location.IsDefault)
            await ClearDefaultAsync(location.PartyId, ct);
        db.SetOriginalVersion(location, input.Version);
        Apply(location, input);
        location.IsDefault = input.IsDefault;
        location.Touch(user.UserId, clock.GetUtcNow());
        db.Audit(user, clock, "party.location_updated", "party", location.PartyId, new { label = Describe(location) });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return AppError.StaleVersion();
        }
        return ToDto(location);
    }

    /// <summary>حذف منطقي: الطلبات والتوريدات المرتبطة بالموقع تبقى كما هي.</summary>
    public async Task<Result<bool>> RemoveAsync(Guid id, CancellationToken ct)
    {
        var location = await db.PartyLocations.FirstOrDefaultAsync(l => l.Id == id, ct);
        if (location is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(location.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (location.DeletedAt is not null)
            return true;
        var now = clock.GetUtcNow();
        location.DeletedAt = now;
        location.IsDefault = false;
        location.Touch(user.UserId, now);
        db.Audit(user, clock, "party.location_removed", "party", location.PartyId, new { label = Describe(location) });
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<Result<LocationDto>> RestoreAsync(Guid id, CancellationToken ct)
    {
        var location = await db.PartyLocations.FirstOrDefaultAsync(l => l.Id == id, ct);
        if (location is null)
            return AppError.NotFound();
        var loaded = await access.LoadEditableAsync(location.PartyId, ct);
        if (!loaded.IsSuccess)
            return loaded.Error!;
        if (location.DeletedAt is not null)
        {
            location.DeletedAt = null;
            location.Touch(user.UserId, clock.GetUtcNow());
            db.Audit(user, clock, "party.location_restored", "party", location.PartyId, new { label = Describe(location) });
            await db.SaveChangesAsync(ct);
        }
        return ToDto(location);
    }

    /// <summary>يتحقق أن الموقع يتبع الطرف نفسه ولم يُحذف (للطلبات والتوريدات).</summary>
    public async Task<AppError?> CheckBelongsAsync(Guid? locationId, Guid partyId, CancellationToken ct) =>
        locationId is { } id && !await db.PartyLocations.AnyAsync(l => l.Id == id && l.PartyId == partyId && l.DeletedAt == null, ct)
            ? AppError.Validation("الموقع المختار لا يتبع هذا العميل أو المورد", "location.not_owned")
            : null;

    private async Task ClearDefaultAsync(Guid partyId, CancellationToken ct)
    {
        var defaults = await db.PartyLocations.Where(l => l.PartyId == partyId && l.IsDefault && l.DeletedAt == null)
            .ToListAsync(ct);
        if (defaults.Count == 0)
            return;
        foreach (var d in defaults)
            d.IsDefault = false;
        // يُحفظ أولًا حتى لا يتعارض مع فهرس «موقع افتراضي واحد».
        await db.SaveChangesAsync(ct);
    }

    private static AppError? Validate(LocationInput input)
    {
        if (input.Id == Guid.Empty || !Enum.IsDefined(input.Kind))
            return AppError.Validation("بيانات الموقع غير مكتملة");
        var url = input.MapsUrl?.Trim();
        if (!string.IsNullOrEmpty(url) && (url.Length > 1000 || !IsMapsUrl(url)))
            return AppError.Validation("الرابط يجب أن يكون رابط Google Maps", "location.invalid_url");
        if ((input.Latitude is null) != (input.Longitude is null)
            || input.Latitude is < -90 or > 90 || input.Longitude is < -180 or > 180)
            return AppError.Validation("الإحداثيات غير صحيحة", "location.invalid_coordinates");
        if (string.IsNullOrWhiteSpace(input.AddressLine) && string.IsNullOrEmpty(url) && input.Latitude is null
            && input.GovernorateId is null && string.IsNullOrWhiteSpace(input.Region))
            return AppError.Validation("أدخل العنوان أو المحافظة أو رابط الخريطة أو الإحداثيات");
        return null;
    }

    private async Task<AppError?> GovernorateErrorAsync(Guid? id, CancellationToken ct) =>
        id is { } g && !await db.LookupItems.AnyAsync(l => l.Id == g && l.Category == LookupCategories.Governorate, ct)
            ? AppError.Validation("محافظة غير معروفة")
            : null;

    private static void Apply(PartyLocation location, LocationInput input)
    {
        location.Kind = input.Kind;
        location.Label = PartyService.Clean(input.Label, 100);
        location.AddressLine = PartyService.Clean(input.AddressLine, 300);
        location.GovernorateId = input.GovernorateId;
        location.Region = PartyService.Clean(input.Region, 100);
        location.MapsUrl = PartyService.Clean(input.MapsUrl, 1000);
        location.Latitude = input.Latitude;
        location.Longitude = input.Longitude;
        location.AccessNotes = PartyService.Clean(input.AccessNotes, 300);
    }

    private static string Describe(PartyLocation l) => l.Label ?? l.Kind switch
    {
        LocationKind.HeadOffice => "المقر الرئيسي",
        LocationKind.Factory => "المصنع",
        LocationKind.Warehouse => "المخزن",
        LocationKind.Loading => "موقع التحميل",
        LocationKind.Delivery => "موقع التسليم",
        _ => "موقع",
    };

    private static LocationDto ToDto(PartyLocation l) => new(l.Id, l.PartyId, l.Kind, l.Label, l.AddressLine, l.MapsUrl,
        l.Latitude, l.Longitude, l.AccessNotes, l.IsDefault, l.Version, l.GovernorateId, l.Region);
}
