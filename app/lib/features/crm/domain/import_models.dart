/// حالة صف في معاينة الاستيراد.
enum ImportStatus {
  newRow('جديد'),
  existing('موجود'),
  duplicate('مكرر'),
  invalid('غير صالح'),
  review('مراجعة');

  const ImportStatus(this.label);
  final String label;

  static ImportStatus parse(String value) => switch (value) {
    'new' => newRow,
    'existing' => existing,
    'duplicate' => duplicate,
    'invalid' => invalid,
    _ => review,
  };
}

class ImportRow {
  const ImportRow({
    required this.row,
    required this.status,
    required this.values,
    required this.notes,
  });

  final int row;
  final ImportStatus status;
  final Map<String, String> values;
  final List<String> notes;

  factory ImportRow.fromJson(Map<String, dynamic> j) => ImportRow(
    row: (j['row'] as num).toInt(),
    status: ImportStatus.parse(j['status'] as String),
    values: (j['values'] as Map).cast<String, String>(),
    notes: (j['notes'] as List).cast<String>(),
  );
}

/// نتيجة المعاينة أو التنفيذ من السيرفر.
class ImportResult {
  const ImportResult({
    required this.kind,
    required this.committed,
    required this.headers,
    required this.mapping,
    required this.counts,
    required this.rows,
    this.previousImportAt,
  });

  final String kind;
  final bool committed;
  final List<String> headers;

  /// الحقل ← رقم العمود كما استخدمه السيرفر.
  final Map<String, int> mapping;
  final Map<ImportStatus, int> counts;
  final List<ImportRow> rows;
  final DateTime? previousImportAt;

  int get importable =>
      counts[ImportStatus.newRow]! +
      counts[ImportStatus.existing]! +
      counts[ImportStatus.duplicate]!;

  factory ImportResult.fromJson(Map<String, dynamic> j) {
    final c = (j['counts'] as Map).cast<String, Object?>();
    int n(String k) => (c[k] as num).toInt();
    return ImportResult(
      kind: j['kind'] as String,
      committed: j['committed'] as bool,
      headers: (j['headers'] as List).cast<String>(),
      mapping: (j['mapping'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()),
      ),
      counts: {
        ImportStatus.newRow: n('new'),
        ImportStatus.existing: n('existing'),
        ImportStatus.duplicate: n('duplicate'),
        ImportStatus.invalid: n('invalid'),
        ImportStatus.review: n('review'),
      },
      rows: (j['rows'] as List)
          .cast<Map<String, dynamic>>()
          .map(ImportRow.fromJson)
          .toList(),
      previousImportAt: j['previousImportAt'] == null
          ? null
          : DateTime.parse(j['previousImportAt'] as String).toLocal(),
    );
  }
}

/// الحقول وأسماؤها لكل نوع استيراد.
const importFields = {
  'parties': {
    'name': 'الاسم',
    'phone': 'الهاتف',
    'grade': 'Grade',
    'type': 'النوع',
  },
  'catalog': {
    'material': 'الخامة',
    'manufacturer': 'الشركة المصنعة',
    'grade': 'Grade',
    'country': 'بلد الصنع',
  },
};
