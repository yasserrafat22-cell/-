import 'auth_models.dart';

/// نتيجة استعادة الجلسة عند فتح التطبيق.
sealed class RestoredSession {
  const RestoredSession();
}

class NoSession extends RestoredSession {
  const NoSession([this.reason]);

  /// سبب إنهاء جلسة سابقة إن وُجد (مثل إلغاء صلاحية الجهاز).
  final AuthFailure? reason;
}

class ActiveSession extends RestoredSession {
  const ActiveSession(this.user, {required this.offline});

  final AuthUser user;

  /// الجلسة مستعادة من التخزين المحلي لتعذر الوصول للسيرفر.
  final bool offline;
}

abstract interface class AuthRepository {
  /// يرمي [AuthException] عند الفشل.
  Future<AuthSession> login({
    required String username,
    required String password,
  });

  Future<RestoredSession> restoreSession();

  /// يغير كلمة المرور ويعيد جلسة جديدة؛ السيرفر يُبطل الجلسات الأخرى.
  /// يرمي [AuthException] عند الفشل.
  Future<AuthSession> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<void> logout();
}
