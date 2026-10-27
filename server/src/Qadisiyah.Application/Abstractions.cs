using Microsoft.EntityFrameworkCore;
using Qadisiyah.Domain.Identity;

namespace Qadisiyah.Application;

public interface IAppDbContext
{
    DbSet<User> Users { get; }
    DbSet<Role> Roles { get; }
    DbSet<UserRole> UserRoles { get; }
    DbSet<RolePermission> RolePermissions { get; }
    DbSet<Device> Devices { get; }
    DbSet<RefreshToken> RefreshTokens { get; }
    DbSet<AuditEntry> AuditEntries { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string hash, string password);
}

public sealed record AccessTokenClaims(
    Guid UserId,
    string Username,
    Guid DeviceId,
    Guid SecurityStamp,
    bool MustChangePassword,
    IReadOnlyCollection<string> Roles,
    IReadOnlyCollection<string> Permissions);

public interface IAccessTokenIssuer
{
    (string Token, DateTimeOffset ExpiresAt) Issue(AccessTokenClaims claims);
}
