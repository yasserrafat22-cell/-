import 'crm_models.dart';

enum AttachmentKind {
  logo('شعار الشركة'),
  productPhoto('صورة منتج'),
  technicalDataSheet('Technical Data Sheet'),
  other('ملف آخر');

  const AttachmentKind(this.nameAr);

  final String nameAr;
}

/// ملف مرفق بعميل أو مورد (المحتوى على السيرفر فقط).
class AttachmentItem {
  const AttachmentItem({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.spec,
    this.createdAt,
    this.createdByName,
  });

  final String id;
  final AttachmentKind kind;
  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// الخامة/الشركة/الـ Grade المرتبطة (ملفات TDS والصور المرتبطة بمنتج).
  final MaterialSpec? spec;
  final DateTime? createdAt;
  final String? createdByName;

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';

  String get sizeLabel => sizeBytes >= 1024 * 1024
      ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).ceil()} KB';

  factory AttachmentItem.fromJson(Json j) => AttachmentItem(
    id: j['id'] as String,
    kind: AttachmentKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => AttachmentKind.other,
    ),
    fileName: j['fileName'] as String,
    contentType: j['contentType'] as String,
    sizeBytes: (j['sizeBytes'] as num).toInt(),
    spec: j['materialId'] == null ? null : MaterialSpec.fromJson(j),
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.parse(j['createdAt'] as String).toLocal(),
    createdByName: j['createdByName'] as String?,
  );
}
