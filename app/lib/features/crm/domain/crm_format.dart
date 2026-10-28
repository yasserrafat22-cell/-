import 'crm_models.dart';

/// تنسيق العرض بالعربية كما في التصميمات: «15 أكتوبر 2026» و«3 طن».
abstract final class CrmFormat {
  static const _months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static String date(DateTime? d) =>
      d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String dateTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${date(d)} — $h:$m ${d.hour < 12 ? 'ص' : 'م'}';
  }

  /// يوم بصيغة السيرفر `yyyy-MM-dd`.
  static String isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String number(double value) {
    final rounded = (value * 100).roundToDouble() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  /// الكمية بالطن من 1000 كجم فأكثر، وإلا بالكيلوجرام.
  static String quantityKg(double? kg) {
    if (kg == null) return '—';
    return kg >= 1000 ? '${number(kg / 1000)} طن' : '${number(kg)} كجم';
  }

  static String unitName(String code) => switch (code) {
    'ton' => 'طن',
    'kg' => 'كجم',
    'bag25' => 'شيكارة',
    _ => code,
  };

  static String status(PartyStatus s, {required bool supplier}) => switch (s) {
    PartyStatus.newParty => supplier ? 'مورد جديد' : 'عميل جديد',
    PartyStatus.active => 'نشط',
    PartyStatus.needsFollowUp => 'يحتاج متابعة',
    PartyStatus.stopped => 'متوقف',
  };

  static String stage(OrderStage s) => switch (s) {
    OrderStage.inquiry => 'استفسار',
    OrderStage.quotation => 'عرض سعر',
    OrderStage.confirmed => 'طلب مؤكد',
    OrderStage.inProgress => 'قيد التنفيذ',
    OrderStage.completed => 'مكتمل',
    OrderStage.cancelled => 'ملغي',
  };

  static String supplyStatus(SupplyStatus s) => switch (s) {
    SupplyStatus.expected => 'متوقع',
    SupplyStatus.received => 'مستلم',
    SupplyStatus.cancelled => 'ملغي',
  };

  static String channel(ContactChannel c) => switch (c) {
    ContactChannel.call => 'اتصال',
    ContactChannel.whatsApp => 'واتساب',
    ContactChannel.visit => 'زيارة',
    ContactChannel.other => 'أخرى',
  };

  /// عرض الرقم المصري بصيغته المحلية (01xxxxxxxxx) والدولي كما هو.
  static String phone(String e164) =>
      e164.startsWith('+20') ? '0${e164.substring(3)}' : e164;
}
