namespace Qadisiyah.Domain.Identity;

public class User
{
    public Guid Id { get; set; } = Guid.CreateVersion7();

    /// <summary>اسم الدخول بعد التطبيع (حروف صغيرة دون مسافات طرفية).</summary>
    public required string Username { get; set; }

    public required string DisplayName { get; set; }

    /// <summary>Hash فقط؛ كلمة المرور لا تُخزن أبدًا.</summary>
    public required string PasswordHash { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>يُفرض عند إنشاء الحساب أو إعادة تعيين كلمة المرور من المدير.</summary>
    public bool MustChangePassword { get; set; }

    /// <summary>يتغير مع كل تغيير لكلمة المرور فيُبطل رموز الدخول السابقة.</summary>
    public Guid SecurityStamp { get; set; } = Guid.NewGuid();

    public int FailedLoginCount { get; set; }
    public DateTimeOffset? LockoutEndsAt { get; set; }
    public DateTimeOffset? LastLoginAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public List<UserRole> Roles { get; } = [];

    public static string NormalizeUsername(string username) =>
        username.Trim().ToLowerInvariant();
}

public class Role
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
    public required string Code { get; set; }
    public required string NameAr { get; set; }

    /// <summary>الأدوار المبدئية لا تُحذف، لكن صلاحياتها قابلة للتعديل.</summary>
    public bool IsSystem { get; set; }

    public List<RolePermission> Permissions { get; } = [];
}

public class UserRole
{
    public Guid UserId { get; set; }
    public Guid RoleId { get; set; }
    public Role? Role { get; set; }
}

public class RolePermission
{
    public Guid RoleId { get; set; }
    public required string Permission { get; set; }
}
