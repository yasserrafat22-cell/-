import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// تذكير متابعة واحد على الهاتف.
class Reminder {
  const Reminder({
    required this.key,
    required this.at,
    required this.title,
    required this.partyId,
  });

  /// معرف المتابعة؛ نفس المعرف = نفس الإشعار (لا تكرار).
  final String key;
  final DateTime at;
  final String title;
  final String partyId;

  /// رقم ثابت للإشعار من معرف المتابعة.
  int get id => key.hashCode & 0x3fffffff;
}

/// إشعارات Android للمتابعات. منفصلة حتى تُستبدل في الاختبارات.
abstract interface class ReminderScheduler {
  /// تجهيز مرة واحدة؛ [onOpen] يفتح ملف السجل عند الضغط على الإشعار.
  Future<void> init(void Function(String partyId) onOpen);

  /// يطلب صلاحية الإشعارات عند الحاجة فقط (أول تذكير).
  Future<bool> ensurePermission();

  /// يستبدل كل التذكيرات المجدولة بهذه القائمة: الجديد يُجدول، والمغلق أو
  /// المتغير موعده يُلغى أو يُحدّث، دون تكرار.
  Future<void> replaceAll(List<Reminder> reminders);

  /// عند تسجيل الخروج: لا تبقى إشعارات ببيانات على جهاز لم يعد مصرحًا له.
  Future<void> clear();
}

class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'follow_ups',
      'تذكير المتابعات',
      channelDescription: 'تذكير بمواعيد متابعة العملاء والموردين',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  @override
  Future<void> init(void Function(String partyId) onOpen) async {
    if (_ready || defaultTargetPlatform != TargetPlatform.android) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload case final id? when id.isNotEmpty) onOpen(id);
      },
    );
    _ready = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      if (launch!.notificationResponse?.payload case final id?
          when id.isNotEmpty) {
        onOpen(id);
      }
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
    return await _android?.areNotificationsEnabled() == true ||
        await _android?.requestNotificationsPermission() == true;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    if (!_ready) return;
    final wanted = {for (final r in reminders) r.id: r};
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (!wanted.containsKey(pending.id)) await _plugin.cancel(id: pending.id);
    }
    for (final r in wanted.values) {
      // نفس الرقم يستبدل الإشعار السابق (موعد جديد) بدل تكراره.
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'موعد متابعة',
        body: r.title,
        payload: r.partyId,
      );
    }
  }

  @override
  Future<void> clear() async {
    if (_ready) await _plugin.cancelAll();
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalReminderScheduler(),
);
