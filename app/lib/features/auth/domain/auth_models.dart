/// المستخدم الحالي كما يعيده السيرفر. الصلاحيات هنا للعرض فقط؛
/// السيرفر هو من يفرضها على كل طلب.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.roles,
    required this.permissions,
    required this.mustChangePassword,
  });

  final String id;
  final String username;
  final String displayName;
  final List<String> roles;
  final Set<String> permissions;
  final bool mustChangePassword;

  bool can(String permission) => permissions.contains(permission);

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
    roles: (json['roles'] as List).cast<String>(),
    permissions: (json['permissions'] as List).cast<String>().toSet(),
    mustChangePassword: json['mustChangePassword'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'roles': roles,
    'permissions': permissions.toList(),
    'mustChangePassword': mustChangePassword,
  };
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['accessToken'] as String,
    accessTokenExpiresAt: DateTime.parse(
      json['accessTokenExpiresAt'] as String,
    ),
    refreshToken: json['refreshToken'] as String,
    refreshTokenExpiresAt: DateTime.parse(
      json['refreshTokenExpiresAt'] as String,
    ),
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
    'refreshToken': refreshToken,
    'refreshTokenExpiresAt': refreshTokenExpiresAt.toIso8601String(),
  };
}

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthUser user;
  final AuthTokens tokens;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    tokens: AuthTokens.fromJson(json),
  );
}

/// أسباب فشل الدخول، ولكل منها رسالة عربية واضحة للمستخدم.
enum AuthFailure {
  invalidCredentials('اسم المستخدم أو كلمة المرور غير صحيحة'),
  accountLocked('تم إيقاف الدخول مؤقتًا بسبب محاولات متكررة. حاول لاحقًا'),
  accountDisabled('هذا الحساب غير مفعّل. تواصل مع مدير النظام'),
  deviceRevoked('تم إلغاء صلاحية هذا الجهاز. تواصل مع مدير النظام'),
  sessionExpired('انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى'),
  wrongCurrentPassword('كلمة المرور الحالية غير صحيحة'),
  weakPassword('كلمة المرور الجديدة غير مقبولة'),
  network('تعذر الاتصال بالسيرفر. تحقق من الاتصال بالإنترنت'),
  server('حدث خطأ في السيرفر. حاول مرة أخرى');

  const AuthFailure(this.message);

  final String message;
}

class AuthException implements Exception {
  const AuthException(this.failure, {this.detail});

  final AuthFailure failure;

  /// رسالة السيرفر العربية عند توفرها (مثل سبب رفض كلمة المرور الجديدة).
  final String? detail;

  String get message => detail ?? failure.message;

  /// أخطاء تعني أن الجلسة لم تعد صالحة ويجب الخروج إلى شاشة الدخول.
  bool get endsSession => const {
    AuthFailure.sessionExpired,
    AuthFailure.deviceRevoked,
    AuthFailure.accountDisabled,
  }.contains(failure);

  @override
  String toString() => 'AuthException(${failure.name})';
}
