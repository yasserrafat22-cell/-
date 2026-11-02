import 'crm_models.dart';
import 'phone_rules.dart';
import 'text_rules.dart';

export 'quick_parse.dart';
export 'text_rules.dart' show latinDigits;

/// «الإدخال السريع»: نماذج اللصق المباشر واستيراد Excel و«بانتظار الاستكمال» والتصدير.
/// السيرفر هو المرجع النهائي للتحقق؛ التحقق هنا للعرض الفوري فقط ونفس قواعده.

const quickFields = [
  'name',
  'phone',
  'material',
  'grade',
  'manufacturer',
  'origin',
  'kind',
];

const quickFieldLabels = {
  'name': 'الاسم',
  'phone': 'رقم الموبايل',
  'material': 'الخامة',
  'grade': 'Grade (اختياري)',
  'manufacturer': 'الشركة المصنعة (اختياري)',
  'origin': 'بلد المنشأ (اختياري)',
  'kind': 'نوع السجل (عميل/مورد)',
};

/// تحذيرات الـ Grade التي تحتاج مراجعة وتأكيدًا صريحًا قبل الحفظ (نفس السيرفر).
const reviewWarnings = {
  'grade_ambiguous',
  'grade_material_mismatch',
  'grade_manufacturer_mismatch',
};

/// أسباب النقص كما يرسلها السيرفر.
String issueLabel(String code) => switch (code) {
  'name_missing' => 'الاسم',
  'name_invalid' => 'اسم غير صالح',
  'phone_missing' => 'رقم الموبايل',
  'phone_invalid' => 'رقم موبايل غير صحيح',
  'material_missing' => 'الخامة',
  'material_unknown' => 'خامة غير موجودة في الكتالوج',
  'grade_missing' => 'بدون Grade',
  'grade_unknown' => 'Grade غير موجود لهذه الخامة',
  'grade_ambiguous' => 'Grade لأكثر من شركة — يحتاج مراجعة',
  'grade_unverified' => 'Grade غير موثق (غير موجود في الكتالوج)',
  'grade_material_mismatch' => 'Grade مسجل لخامة أخرى — يحتاج مراجعة',
  'grade_manufacturer_mismatch' =>
    'Grade لا يطابق الشركة المصنعة — يحتاج مراجعة',
  'origin_unknown' => 'بلد المنشأ غير موجود في القائمة',
  'kind_missing' => 'نوع السجل',
  _ => code,
};

String kindLabel(String? kind) => switch (kind) {
  'customer' => 'عميل',
  'supplier' => 'مورد',
  _ => 'غير محدد',
};

/// نوع السجل في الاستيراد المختلط بكلمات واضحة فقط (نفس قاعدة السيرفر).
String? parseKind(String? value) {
  final t = (value ?? '').trim().toLowerCase();
  const customers = {
    'عميل',
    'عملاء',
    'العميل',
    'العملاء',
    'customer',
    'customers',
    'client',
  };
  const suppliers = {
    'مورد',
    'موردين',
    'المورد',
    'الموردون',
    'الموردين',
    'supplier',
    'suppliers',
    'vendor',
  };
  if (customers.contains(t)) return 'customer';
  if (suppliers.contains(t)) return 'supplier';
  return null;
}

/// صف قبل الإرسال (من اللصق أو Excel) مع تصحيحات المستخدم.
class EntryRow {
  EntryRow({
    required this.id,
    required this.row,
    this.kind,
    this.name,
    this.phone,
    this.material,
    this.grade,
    this.manufacturer,
    this.materialId,
    this.gradeId,
    this.origin,
    this.reviewAcknowledged = false,
    this.flags = const [],
  });

  final String id;
  final int row;
  String? kind;
  String? name;
  String? phone;
  String? material;
  String? grade;
  String? manufacturer;
  String? materialId;
  String? gradeId;

  /// بلد المنشأ كما كُتب (اختياري).
  String? origin;

  /// أكد المستخدم مراجعة تحذيرات الـ Grade الملتبس.
  bool reviewAcknowledged;

  /// أعلام المحلل للمراجعة (لا تُرسل للسيرفر): multiple_phones، grade_uncertain...
  final List<String> flags;

  /// استبعده المستخدم من الدفعة.
  bool excluded = false;

  Json toJson() => {
    'id': id,
    'row': row,
    'kind': kind,
    'name': name,
    'phone': phone,
    'material': material,
    'grade': grade,
    'manufacturer': manufacturer,
    'materialId': materialId,
    'gradeId': gradeId,
    'origin': origin,
    'reviewAcknowledged': reviewAcknowledged,
  };
}

/// نتيجة صف من السيرفر (معاينة أو تنفيذ).
class RowResult {
  const RowResult({
    required this.id,
    required this.row,
    required this.status,
    required this.issues,
    this.kind,
    this.materialId,
    this.gradeId,
    this.materialCode,
    this.gradeLabel,
    this.partyId,
    this.duplicateOfId,
    this.duplicateName,
    this.note,
    this.warnings = const [],
    this.unverifiedGrade,
    this.needsReview = false,
    this.errorCode,
  });

  final String id;
  final int row;

  /// ready أو needs_review (معاينة) أو completed أو pending أو duplicate أو failed.
  final String status;

  /// العوائق فقط.
  final List<String> issues;

  /// تحذيرات لا تمنع الحفظ (منها تحذيرات المراجعة).
  final List<String> warnings;
  final String? unverifiedGrade;
  final bool needsReview;

  /// كود خطأ معالجة غير متوقع (يختلف عن النقص والتحذير).
  final String? errorCode;
  final String? kind;
  final String? materialId;
  final String? gradeId;
  final String? materialCode;
  final String? gradeLabel;
  final String? partyId;
  final String? duplicateOfId;
  final String? duplicateName;
  final String? note;

  factory RowResult.fromJson(Json j) => RowResult(
    id: j['id'] as String,
    row: (j['row'] as num).toInt(),
    status: j['status'] as String,
    issues: (j['issues'] as List? ?? const []).cast<String>(),
    kind: j['kind'] as String?,
    materialId: j['materialId'] as String?,
    gradeId: j['gradeId'] as String?,
    materialCode: j['materialCode'] as String?,
    gradeLabel: j['gradeLabel'] as String?,
    partyId: j['partyId'] as String?,
    duplicateOfId: j['duplicateOfId'] as String?,
    duplicateName: j['duplicateName'] as String?,
    note: j['note'] as String?,
    warnings: (j['warnings'] as List? ?? const []).cast<String>(),
    unverifiedGrade: j['unverifiedGrade'] as String?,
    needsReview: j['needsReview'] as bool? ?? false,
    errorCode: j['errorCode'] as String?,
  );
}

class BatchResult {
  const BatchResult({
    required this.batchId,
    required this.committed,
    required this.total,
    required this.created,
    required this.pending,
    required this.duplicate,
    required this.failed,
    required this.rows,
  });

  final String batchId;
  final bool committed;
  final int total;
  final int created;
  final int pending;
  final int duplicate;
  final int failed;
  final List<RowResult> rows;

  factory BatchResult.fromJson(Json j) => BatchResult(
    batchId: j['batchId'] as String,
    committed: j['committed'] as bool? ?? false,
    total: (j['total'] as num).toInt(),
    created: (j['created'] as num).toInt(),
    pending: (j['pending'] as num).toInt(),
    duplicate: (j['duplicate'] as num).toInt(),
    failed: (j['failed'] as num).toInt(),
    rows: [
      for (final r in (j['rows'] as List).cast<Json>()) RowResult.fromJson(r),
    ],
  );
}

/// صف «بانتظار الاستكمال» (ليس عميلًا أو موردًا بعد).
class PendingEntry {
  const PendingEntry({
    required this.id,
    required this.batchId,
    required this.row,
    required this.status,
    required this.issues,
    required this.createdAt,
    this.method,
    this.kind,
    this.name,
    this.phone,
    this.material,
    this.grade,
    this.manufacturer,
    this.materialId,
    this.gradeId,
    this.materialCode,
    this.gradeLabel,
    this.duplicateOfId,
    this.duplicateName,
    this.note,
    this.partyId,
    this.createdByName,
    this.origin,
    this.warnings = const [],
    this.unverifiedGrade,
    this.needsReview = false,
    this.reviewAcknowledged = false,
    this.errorCode,
  });

  final String id;
  final String batchId;
  final String? origin;
  final List<String> warnings;
  final String? unverifiedGrade;
  final bool needsReview;
  final bool reviewAcknowledged;
  final String? errorCode;
  final String? method;
  final int row;
  final String? kind;
  final String? name;
  final String? phone;
  final String? material;
  final String? grade;
  final String? manufacturer;
  final String? materialId;
  final String? gradeId;
  final String? materialCode;
  final String? gradeLabel;
  final String status;
  final List<String> issues;
  final String? duplicateOfId;
  final String? duplicateName;
  final String? note;
  final String? partyId;
  final DateTime createdAt;
  final String? createdByName;

  factory PendingEntry.fromJson(Json j) => PendingEntry(
    id: j['id'] as String,
    batchId: j['batchId'] as String,
    method: j['method'] as String?,
    row: (j['row'] as num).toInt(),
    kind: j['kind'] as String?,
    name: j['name'] as String?,
    phone: j['phone'] as String?,
    material: j['material'] as String?,
    grade: j['grade'] as String?,
    manufacturer: j['manufacturer'] as String?,
    materialId: j['materialId'] as String?,
    gradeId: j['gradeId'] as String?,
    materialCode: j['materialCode'] as String?,
    gradeLabel: j['gradeLabel'] as String?,
    status: j['status'] as String,
    issues: (j['issues'] as List? ?? const []).cast<String>(),
    duplicateOfId: j['duplicateOfId'] as String?,
    duplicateName: j['duplicateName'] as String?,
    note: j['note'] as String?,
    partyId: j['partyId'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    createdByName: j['createdByName'] as String?,
    origin: j['origin'] as String?,
    warnings: (j['warnings'] as List? ?? const []).cast<String>(),
    unverifiedGrade: j['unverifiedGrade'] as String?,
    needsReview: j['needsReview'] as bool? ?? false,
    reviewAcknowledged: j['reviewAcknowledged'] as bool? ?? false,
    errorCode: j['errorCode'] as String?,
  );
}

class PendingPage {
  const PendingPage(this.items, this.total);

  final List<PendingEntry> items;
  final int total;
}

/// ورقة Excel كما قرأها السيرفر، مع تعيين مقترح للأعمدة.
class ExcelSheetData {
  const ExcelSheetData({
    required this.name,
    required this.headers,
    required this.rows,
    required this.mapping,
    this.headerRow = 1,
    this.sourceRows,
  });

  final String name;
  final List<String> headers;
  final List<List<String>> rows;
  final Map<String, int> mapping;

  /// رقم صف العناوين في الملف (يبدأ من 1).
  final int headerRow;

  /// رقم كل صف بيانات في الملف الأصلي (null مع السيرفر الأقدم).
  final List<int>? sourceRows;

  factory ExcelSheetData.fromJson(Json j) => ExcelSheetData(
    name: j['name'] as String,
    headers: (j['headers'] as List).cast<String>(),
    rows: [for (final r in (j['rows'] as List)) (r as List).cast<String>()],
    mapping: {
      for (final e in (j['mapping'] as Map).entries)
        e.key as String: (e.value as num).toInt(),
    },
    headerRow: (j['headerRow'] as num?)?.toInt() ?? 1,
    sourceRows: (j['sourceRows'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList(),
  );
}

class ExportItem {
  const ExportItem({
    required this.kind,
    required this.partyId,
    required this.name,
    this.phone,
    this.material,
    this.grade,
    this.manufacturer,
  });

  final String kind;
  final String partyId;
  final String name;
  final String? phone;
  final String? material;
  final String? grade;
  final String? manufacturer;

  factory ExportItem.fromJson(Json j) => ExportItem(
    kind: j['kind'] as String,
    partyId: j['partyId'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String?,
    material: j['material'] as String?,
    grade: j['grade'] as String?,
    manufacturer: j['manufacturer'] as String?,
  );
}

class ExportData {
  const ExportData(this.customers, this.suppliers, this.rows);

  final int customers;
  final int suppliers;
  final List<ExportItem> rows;

  factory ExportData.fromJson(Json j) => ExportData(
    (j['customers'] as num).toInt(),
    (j['suppliers'] as num).toInt(),
    [for (final r in (j['rows'] as List).cast<Json>()) ExportItem.fromJson(r)],
  );
}

class BatchSummary {
  const BatchSummary({
    required this.id,
    required this.rowCount,
    required this.created,
    required this.pending,
    required this.duplicate,
    required this.failed,
    required this.createdAt,
    this.method,
    this.audience,
    this.fileName,
    this.status,
    this.createdByName,
  });

  final String id;
  final String? method;
  final String? audience;
  final String? fileName;
  final int rowCount;
  final int created;
  final int pending;
  final int duplicate;
  final int failed;
  final String? status;
  final DateTime createdAt;
  final String? createdByName;

  factory BatchSummary.fromJson(Json j) => BatchSummary(
    id: j['id'] as String,
    method: j['method'] as String?,
    audience: j['audience'] as String?,
    fileName: j['fileName'] as String?,
    rowCount: (j['rowCount'] as num).toInt(),
    created: (j['created'] as num).toInt(),
    pending: (j['pending'] as num).toInt(),
    duplicate: (j['duplicate'] as num).toInt(),
    failed: (j['failed'] as num).toInt(),
    status: j['status'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    createdByName: j['createdByName'] as String?,
  );
}

// ---------------- التحقق الفوري (نفس قواعد السيرفر) ----------------

/// الرقم بصيغة 01xxxxxxxxx إن كان موبايلًا مصريًا صحيحًا (بنفس قاعدة السيرفر: +20 و0020
/// و20، والرقم بلا الصفر الأول الذي يحذفه Excel)، وإلا الرقم كما كُتب دون مسافات.
String normalizeMobile(String input) =>
    egyptianMobileOrNull(input) ??
    localMobile(latinDigits(input).replaceAll(RegExp(r'[\s\-().]'), ''));

/// نتيجة التحقق المحلي بنفس أكواد السيرفر: العوائق تمنع إنشاء البطاقة، والتحذيرات لا تمنعه.
class LocalCheck {
  const LocalCheck(
    this.kind,
    this.material,
    this.grade,
    this.issues, {
    this.warnings = const [],
    this.unverifiedGrade,
    this.origin,
  });

  final String? kind;
  final MaterialItem? material;

  /// Grade الكتالوج عند مطابقة وحيدة مؤكدة فقط.
  final GradeItem? grade;

  /// العوائق: الاسم، الموبايل، الخامة، النوع.
  final List<String> issues;

  /// تحذيرات الـ Grade والمنشأ.
  final List<String> warnings;

  /// نص الـ Grade الذي سيُحفظ «غير موثق».
  final String? unverifiedGrade;
  final LookupItem? origin;

  /// بلا عوائق (قد يحتاج مراجعة).
  bool get complete => issues.isEmpty;

  bool get needsReview => warnings.any(reviewWarnings.contains);

  /// ready أو needs_review أو pending (ناقص)، كما يحكم السيرفر.
  String status({bool acknowledged = false}) => !complete
      ? 'pending'
      : needsReview && !acknowledged
      ? 'needs_review'
      : 'ready';
}

/// الخامة بالكود أو المرادف أو الاسم البديل أو الاسم العربي/الإنجليزي (مطابقة تامة بعد التطبيع).
MaterialItem? materialFor(ReferenceData refs, String text) {
  final normalized = normalizeText(text);
  if (normalized.isEmpty) return null;
  final key = normalizeCode(synonymMaterialCode(normalized) ?? text);
  return refs.materials
      .where(
        (m) =>
            normalizeCode(m.code) == key ||
            m.aliases.any((a) => normalizeCode(a) == key) ||
            normalizeCode(m.nameAr) == key ||
            (m.nameEn != null && normalizeCode(m.nameEn) == key),
      )
      .firstOrNull;
}

/// نفس قواعد `QuickEntryService.Resolve` في السيرفر.
LocalCheck checkRow(EntryRow r, String audience, ReferenceData refs) {
  final issues = <String>[];
  final warnings = <String>[];
  final kind = audience != 'mixed'
      ? audience
      : (r.kind == 'customer' || r.kind == 'supplier')
      ? r.kind
      : parseKind(r.kind);
  if (kind == null) issues.add('kind_missing');

  final name = (r.name ?? '').trim().split(RegExp(r'\s+')).join(' ');
  if (name.isEmpty) {
    issues.add('name_missing');
  } else if (name.length < 2 || name.length > 200) {
    issues.add('name_invalid');
  }

  if ((r.phone ?? '').trim().isEmpty) {
    issues.add('phone_missing');
  } else if (egyptianMobileOrNull(r.phone) == null) {
    issues.add('phone_invalid');
  }

  final gradeText = (r.grade ?? '').trim().isEmpty ? null : r.grade!.trim();
  final makerText = (r.manufacturer ?? '').trim().isEmpty
      ? null
      : r.manufacturer!.trim();
  final picked = r.gradeId == null ? null : refs.grade(r.gradeId!);
  MaterialItem? pickedMaterial() =>
      refs.materials.where((m) => m.grades.contains(picked)).firstOrNull;
  MaterialItem? material;
  if (r.materialId != null) {
    material = refs.material(r.materialId!);
  } else if (picked != null) {
    material = pickedMaterial();
  } else if ((r.material ?? '').trim().isNotEmpty) {
    material = materialFor(refs, r.material!);
  }
  if (material == null) {
    issues.add(
      r.materialId == null &&
              (r.material ?? '').trim().isEmpty &&
              picked == null
          ? 'material_missing'
          : 'material_unknown',
    );
  }

  GradeItem? grade;
  var unverifiedText = gradeText;
  if (picked != null) {
    if (material != null && !material.grades.contains(picked)) {
      warnings.add('grade_material_mismatch');
      unverifiedText ??= picked.code;
    } else {
      grade = picked;
    }
  } else if (material == null) {
    // تحذيرات الـ Grade تخص خامة معروفة؛ بدونها يكفي عائق الخامة.
  } else if (r.gradeId != null) {
    warnings.add(gradeText == null ? 'grade_missing' : 'grade_unverified');
  } else if (gradeText == null) {
    warnings.add('grade_missing');
  } else {
    final code = normalizeCode(gradeText);
    final same = [
      for (final g in material.grades)
        if (normalizeCode(g.code) == code) g,
    ];
    var candidates = same;
    if (makerText != null && same.isNotEmpty) {
      final variants = makerVariants(normalizeText(makerText));
      candidates = [
        for (final g in same)
          if (g.manufacturerId != null &&
              variants.contains(
                normalizeText(refs.manufacturer(g.manufacturerId!)?.name),
              ))
            g,
      ];
    }
    if (candidates.length == 1) {
      grade = candidates.single;
    } else if (candidates.length > 1) {
      warnings.add('grade_ambiguous');
    } else if (same.isNotEmpty) {
      warnings.add('grade_manufacturer_mismatch');
    } else if (code.isNotEmpty &&
        refs.materials.any(
          (m) => m.grades.any((g) => normalizeCode(g.code) == code),
        )) {
      warnings.add('grade_material_mismatch');
    } else {
      warnings.add('grade_unverified');
    }
  }

  LookupItem? origin;
  if ((r.origin ?? '').trim().isNotEmpty) {
    final key = normalizeText(r.origin);
    final matches = [
      for (final c in refs.countries)
        if (normalizeText(c.nameAr) == key || normalizeText(c.code) == key) c,
    ];
    if (matches.length == 1) {
      origin = matches.single;
    } else {
      warnings.add('origin_unknown');
    }
  }

  return LocalCheck(
    kind,
    material,
    grade,
    issues,
    warnings: warnings,
    unverifiedGrade: grade == null ? unverifiedText : null,
    origin: origin,
  );
}

/// الصفوف من الخلايا حسب التعيين. [sourceRows] أرقام الصفوف في الملف الأصلي (Excel).
List<EntryRow> rowsFrom(
  List<List<String>> cells,
  Map<String, int> mapping, {
  required String Function() newId,
  String? kind,
  int firstRow = 1,
  List<int>? sourceRows,
  List<List<String>>? flags,
}) => [
  for (final (i, r) in cells.indexed)
    if (r.any((c) => c.trim().isNotEmpty))
      EntryRow(
        id: newId(),
        row: sourceRows != null && i < sourceRows.length
            ? sourceRows[i]
            : firstRow + i,
        kind: kind ?? _cell(r, mapping['kind']),
        name: _cell(r, mapping['name']),
        phone: _cell(r, mapping['phone']),
        material: _cell(r, mapping['material']),
        grade: _cell(r, mapping['grade']),
        manufacturer: _cell(r, mapping['manufacturer']),
        origin: _cell(r, mapping['origin']),
        flags: flags != null && i < flags.length ? flags[i] : const [],
      ),
];

String? _cell(List<String> r, int? c) =>
    c == null || c < 0 || c >= r.length || r[c].trim().isEmpty
    ? null
    : r[c].trim();
