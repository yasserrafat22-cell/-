import 'crm_models.dart';

enum FollowUpStatus { overdue, today, upcoming }

/// متابعة مفتوحة (من آخر تواصل مسجل) كما يعيدها السيرفر.
class FollowUpItem {
  const FollowUpItem({
    required this.interactionId,
    required this.partyId,
    required this.partyName,
    required this.isCustomer,
    required this.dueAt,
    required this.status,
    required this.remind,
    required this.mine,
    this.representativeName,
    this.notes,
  });

  final String interactionId;
  final String partyId;
  final String partyName;
  final bool isCustomer;
  final DateTime dueAt;
  final FollowUpStatus status;

  /// «تذكير بالمتابعة» مفعّل: يصدر إشعار على الهاتف.
  final bool remind;

  /// المستخدم هو المندوب المسؤول أو من سجّل المتابعة (الإشعار له فقط).
  final bool mine;
  final String? representativeName;
  final String? notes;

  factory FollowUpItem.fromJson(Json j) => FollowUpItem(
    interactionId: j['interactionId'] as String,
    partyId: j['partyId'] as String,
    partyName: j['partyName'] as String,
    isCustomer: j['isCustomer'] as bool? ?? true,
    dueAt: DateTime.parse(j['dueAt'] as String).toLocal(),
    status: FollowUpStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => FollowUpStatus.upcoming,
    ),
    remind: j['remind'] as bool? ?? false,
    mine: j['mine'] as bool? ?? false,
    representativeName: j['representativeName'] as String?,
    notes: j['notes'] as String?,
  );
}
