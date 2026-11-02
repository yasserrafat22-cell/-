import 'crm_models.dart';
import 'phone_rules.dart';

/// «الإدخال السريع»: نماذج اللصق المباشر واستيراد Excel و«بانتظار الاستكمال» والتصدير.
/// السيرفر هو المرجع النهائي للتحقق؛ التحقق هنا للعرض الفوري فقط ونفس قواعده.

const quickFields = [
  'name',
  'phone',
  'material',
  'grade',
  'manufacturer',
  'kind',
];

const quickFieldLabels = {
  'name': 'الاسم',
  'phone': 'رقم الموبايل',
  'material': 'الخامة',
  'grade': 'Grade',
  'manufacturer': 'الشركة المصنعة (اختياري)',
  'kind': 'نوع السجل (عميل/مورد)',
};

/// أسباب النقص كما يرسلها السيرفر.
String issueLabel(String code) => switch (code) {
  'name_missing' => 'الاسم',
  'name_invalid' => 'اسم غير صالح',
  'phone_missing' => 'رقم الموبايل',
  'phone_invalid' => 'رقم موبايل غير صحيح',
  'material_missing' => 'الخامة',
  'material_unknown' => 'خامة غير موجودة في الكتالوج',
  'grade_missing' => 'Grade',
  'grade_unknown' => 'Grade غير موجود لهذه الخامة',
  'grade_ambiguous' => 'Grade لأكثر من شركة — حدده',
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
  });

  final String id;
  final int row;

  /// ready (معاينة) أو completed أو pending أو duplicate أو failed.
  final String status;
  final List<String> issues;
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
  });

  final String id;
  final String batchId;
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
  });

  final String name;
  final List<String> headers;
  final List<List<String>> rows;
  final Map<String, int> mapping;

  factory ExcelSheetData.fromJson(Json j) => ExcelSheetData(
    name: j['name'] as String,
    headers: (j['headers'] as List).cast<String>(),
    rows: [for (final r in (j['rows'] as List)) (r as List).cast<String>()],
    mapping: {
      for (final e in (j['mapping'] as Map).entries)
        e.key as String: (e.value as num).toInt(),
    },
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

/// الرقم كما كُتب بعد توحيد الأرقام والمسافات؛ 10 أرقام تبدأ بـ 1 (Excel يحذف الصفر) تُكمل
/// بالصفر لأنها غير ملتبسة. أي رقم آخر لا يُخمن.
String normalizeMobile(String input) {
  var d = latinDigits(input).replaceAll(RegExp(r'[\s\-().]'), '');
  if (RegExp(r'^1[0125]\d{8}$').hasMatch(d)) d = '0$d';
  return localMobile(d);
}

/// الخامة والـ Grade كما يحددهما الكتالوج الموحد (أو null)، والنقص بنفس أكواد السيرفر.
class LocalCheck {
  const LocalCheck(this.kind, this.material, this.grade, this.issues);

  final String? kind;
  final MaterialItem? material;
  final GradeItem? grade;
  final List<String> issues;

  bool get complete => issues.isEmpty;
}

LocalCheck checkRow(EntryRow r, String audience, ReferenceData refs) {
  final issues = <String>[];
  final kind = audience != 'mixed'
      ? audience
      : (r.kind == 'customer' || r.kind == 'supplier')
      ? r.kind
      : parseKind(r.kind);
  if (kind == null) issues.add('kind_missing');

  final name = (r.name ?? '').trim();
  if (name.isEmpty) {
    issues.add('name_missing');
  } else if (name.length < 2 || name.length > 200) {
    issues.add('name_invalid');
  }

  if ((r.phone ?? '').trim().isEmpty) {
    issues.add('phone_missing');
  } else if (!egyptianMobile.hasMatch(normalizeMobile(r.phone!))) {
    issues.add('phone_invalid');
  }

  GradeItem? grade;
  MaterialItem? material;
  if (r.gradeId != null) {
    grade = refs.grade(r.gradeId!);
    if (grade == null) issues.add('grade_unknown');
  }
  if (r.materialId != null) {
    material = refs.material(r.materialId!);
  } else if (grade != null) {
    material = refs.materials
        .where((m) => m.grades.contains(grade))
        .firstOrNull;
  } else if ((r.material ?? '').trim().isNotEmpty) {
    material = _material(refs, r.material!);
  }
  if (material == null) {
    issues.add(
      r.materialId == null && (r.material ?? '').trim().isEmpty && grade == null
          ? 'material_missing'
          : 'material_unknown',
    );
  }
  if (grade != null && material != null && !material.grades.contains(grade)) {
    issues.add('grade_unknown');
    grade = null;
  }
  if (grade == null && r.gradeId == null) {
    if ((r.grade ?? '').trim().isEmpty) {
      issues.add('grade_missing');
    } else if (material != null) {
      final key = _code(r.grade!);
      var candidates = material.grades
          .where((g) => _code(g.code) == key)
          .toList();
      final maker = (r.manufacturer ?? '').trim().toLowerCase();
      if (maker.isNotEmpty) {
        candidates = [
          for (final g in candidates)
            if (g.manufacturerId != null &&
                refs.manufacturer(g.manufacturerId!)?.name.toLowerCase() ==
                    maker)
              g,
        ];
      }
      if (candidates.length == 1) {
        grade = candidates.single;
      } else {
        issues.add(candidates.isEmpty ? 'grade_unknown' : 'grade_ambiguous');
      }
    }
  }
  return LocalCheck(kind, material, grade, issues);
}

// ---------------- اللصق المباشر ----------------

/// نتيجة تقسيم النص الملصوق: الخلايا، وتعيين مقترح للأعمدة يؤكده المستخدم.
class PasteParse {
  const PasteParse(this.cells, this.mapping, {required this.free});

  /// خلايا كل سطر.
  final List<List<String>> cells;

  /// الحقل ← رقم العمود (مقترح من المحتوى فقط).
  final Map<String, int> mapping;

  /// أسطر نصية حرة (واتساب) استُخرج منها الرقم والخامة والـ Grade، والباقي اسم.
  final bool free;

  int get columns => cells.fold(0, (m, r) => r.length > m ? r.length : m);
}

final _mobileToken = RegExp(r'(?:\+?20|0020)?\s*0?1[0125](?:[\s\-]?\d){8}');

/// الأرقام العربية والفارسية إلى لاتينية (الرقم كما كُتب دون تخمين).
String latinDigits(String s) {
  final b = StringBuffer();
  for (final c in s.runes) {
    if (c >= 0x660 && c <= 0x669) {
      b.writeCharCode(c - 0x660 + 48);
    } else if (c >= 0x6F0 && c <= 0x6F9) {
      b.writeCharCode(c - 0x6F0 + 48);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

String _code(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_./]'), '');

/// يقسم النص الملصوق:
/// - بأعمدة الجدول (Tab) إن وُجدت، أو بالفواصل (، أو ,) إن تساوى عددها في كل الأسطر؛
/// - وإلا فالسطر نص حر: يُستخرج منه رقم الموبايل، والخامة والـ Grade إن طابقا الكتالوج حرفيًا، والباقي اسم.
/// الاسم الذي يحتوي فواصل لا يُقسم ما لم تكن الأسطر كلها بنفس عدد الأعمدة.
PasteParse parsePaste(String text, ReferenceData refs) {
  final lines = [
    for (final l in latinDigits(text).split(RegExp(r'\r?\n')))
      if (l.trim().isNotEmpty) l,
  ];
  if (lines.isEmpty) return const PasteParse([], {}, free: false);

  List<List<String>>? grid;
  if (lines.every((l) => l.contains('\t'))) {
    grid = [for (final l in lines) l.split('\t').map((c) => c.trim()).toList()];
  } else {
    final sep = RegExp(r'[,،;؛]');
    final counts = lines.map((l) => sep.allMatches(l).length).toSet();
    if (counts.length == 1 && counts.first > 0) {
      grid = [
        for (final l in lines) l.split(sep).map((c) => c.trim()).toList(),
      ];
    }
  }
  if (grid != null) {
    return PasteParse(grid, suggestMapping(grid, refs), free: false);
  }

  // نص حر: [الاسم، الرقم، الخامة، Grade].
  final rows = <List<String>>[];
  for (final l in lines) {
    var rest = l;
    final phone = _mobileToken.firstMatch(rest)?.group(0)?.trim() ?? '';
    if (phone.isNotEmpty) rest = rest.replaceFirst(phone, ' ');
    String material = '', grade = '';
    final tokens = rest
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final kept = <String>[];
    for (final t in tokens) {
      final m = material.isEmpty ? _material(refs, t) : null;
      if (m != null) {
        material = t;
        continue;
      }
      if (grade.isEmpty && _gradeExists(refs, t, material)) {
        grade = t;
        continue;
      }
      kept.add(t);
    }
    rows.add([
      kept.join(' ').replaceAll(RegExp(r'^[\s\-–:،,]+|[\s\-–:،,]+$'), ''),
      phone,
      material,
      grade,
    ]);
  }
  return PasteParse(rows, const {
    'name': 0,
    'phone': 1,
    'material': 2,
    'grade': 3,
  }, free: true);
}

MaterialItem? _material(ReferenceData refs, String text) {
  final key = _code(text);
  if (key.isEmpty) return null;
  return refs.materials.where((m) => _code(m.code) == key).firstOrNull;
}

bool _gradeExists(ReferenceData refs, String text, String material) {
  final key = _code(text);
  if (key.length < 2) return false;
  final scope = material.isEmpty
      ? refs.materials
      : refs.materials.where((m) => _code(m.code) == _code(material));
  return scope.any((m) => m.grades.any((g) => _code(g.code) == key));
}

/// تعيين مقترح من المحتوى: عمود الأرقام = الموبايل، ما يطابق الخامات = الخامة، ما يطابق الـ Grades =
/// Grade، كلمات عميل/مورد = النوع، وأطول نص = الاسم. أقل من الأغلبية لا يُقترح (يحدده المستخدم).
Map<String, int> suggestMapping(List<List<String>> grid, ReferenceData refs) {
  final width = grid.fold(0, (m, r) => r.length > m ? r.length : m);
  final map = <String, int>{};
  double share(int c, bool Function(String) test) {
    final values = [
      for (final r in grid)
        if (c < r.length && r[c].trim().isNotEmpty) r[c].trim(),
    ];
    return values.isEmpty ? 0 : values.where(test).length / values.length;
  }

  void pick(String field, bool Function(String) test) {
    var best = -1;
    var bestShare = 0.5;
    for (var c = 0; c < width; c++) {
      if (map.containsValue(c)) continue;
      final s = share(c, test);
      if (s > bestShare) {
        best = c;
        bestShare = s;
      }
    }
    if (best >= 0) map[field] = best;
  }

  pick(
    'phone',
    (v) => _mobileToken.hasMatch(v) && RegExp(r'^[\d\s+\-]+$').hasMatch(v),
  );
  pick('kind', (v) => parseKind(v) != null);
  pick('material', (v) => _material(refs, v) != null);
  pick('grade', (v) => _gradeExists(refs, v, ''));
  pick('name', (v) => RegExp(r'[A-Za-z؀-ۿ]').hasMatch(v) && v.length >= 2);
  return map;
}

/// الصفوف من الخلايا حسب التعيين.
List<EntryRow> rowsFrom(
  List<List<String>> cells,
  Map<String, int> mapping, {
  required String Function() newId,
  String? kind,
  int firstRow = 1,
}) => [
  for (final (i, r) in cells.indexed)
    if (r.any((c) => c.trim().isNotEmpty))
      EntryRow(
        id: newId(),
        row: firstRow + i,
        kind: kind ?? _cell(r, mapping['kind']),
        name: _cell(r, mapping['name']),
        phone: _cell(r, mapping['phone']),
        material: _cell(r, mapping['material']),
        grade: _cell(r, mapping['grade']),
        manufacturer: _cell(r, mapping['manufacturer']),
      ),
];

String? _cell(List<String> r, int? c) =>
    c == null || c < 0 || c >= r.length || r[c].trim().isEmpty
    ? null
    : r[c].trim();
