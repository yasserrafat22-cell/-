import 'crm_models.dart';

/// موظف أو جهة اتصال داخل الشركة.
class PartyContact {
  const PartyContact({
    required this.id,
    required this.name,
    this.jobTitle,
    this.mobile,
    this.isPrimary = false,
    this.version = 0,
  });

  final String id;
  final String name;
  final String? jobTitle;

  /// بصيغة E.164 كما حفظها السيرفر.
  final String? mobile;
  final bool isPrimary;
  final int version;

  factory PartyContact.fromJson(Json j) => PartyContact(
    id: j['id'] as String,
    name: j['name'] as String,
    jobTitle: j['jobTitle'] as String?,
    mobile: j['mobile'] as String?,
    isPrimary: j['isPrimary'] as bool? ?? false,
    version: (j['version'] as num?)?.toInt() ?? 0,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'jobTitle': jobTitle,
    'mobile': mobile,
    'isPrimary': isPrimary,
    'version': version,
  };
}
