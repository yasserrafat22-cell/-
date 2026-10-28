import 'crm_models.dart';

/// دقة مواصفات الخامة كما يحسبها السيرفر.
enum SpecPrecision {
  /// Grade محدد من شركة معروفة.
  exact,

  /// Grade محدد لكن شركته غير معروفة (بيانات سابقة).
  unknownManufacturer,

  /// النوع فقط ولم يُحدد الـ Grade.
  unspecified,

  /// العميل يقبل أي شركة وأي Grade.
  open,
}

SpecPrecision _precision(Object? v) => switch (v) {
  'exact' => SpecPrecision.exact,
  'unknownManufacturer' => SpecPrecision.unknownManufacturer,
  'open' => SpecPrecision.open,
  _ => SpecPrecision.unspecified,
};

/// مواصفات خامة محفوظة: النوع · الشركة المصنّعة · Grade · بلد الصنع.
class MaterialSpec {
  const MaterialSpec({
    required this.materialId,
    required this.materialCode,
    this.gradeId,
    this.gradeCode,
    this.manufacturerId,
    this.manufacturerName,
    this.originId,
    this.originName,
    this.precision = SpecPrecision.unspecified,
    this.gradeVerified = true,
  });

  final String materialId;
  final String materialCode;
  final String? gradeId;
  final String? gradeCode;
  final String? manufacturerId;
  final String? manufacturerName;
  final String? originId;
  final String? originName;
  final SpecPrecision precision;
  final bool gradeVerified;

  bool get isOpen => precision == SpecPrecision.open;

  /// الأجزاء بالترتيب المعتمد. الشركة تُكتب صراحةً: «أي شركة» للمواصفات
  /// المفتوحة و«الشركة غير محددة» للبيانات السابقة، ولا تُحذف بصمت.
  List<String> get parts {
    final maker = switch (precision) {
      SpecPrecision.open => 'أي شركة',
      SpecPrecision.unknownManufacturer => 'الشركة غير محددة',
      _ => manufacturerName,
    };
    return [materialCode, ?maker, ?gradeCode, ?originName];
  }

  String get label => parts.join(' · ');

  /// يقرأ المواصفات من بند يحتوي `spec` (السيرفر الحالي) أو الحقول القديمة.
  factory MaterialSpec.fromJson(Json j) {
    final spec = j['spec'] as Json?;
    final gradeCode = (spec?['gradeCode'] ?? j['gradeCode']) as String?;
    return MaterialSpec(
      materialId: j['materialId'] as String,
      materialCode: (spec?['materialCode'] ?? j['materialCode']) as String,
      gradeId: j['gradeId'] as String?,
      gradeCode: gradeCode,
      manufacturerId: spec?['manufacturerId'] as String?,
      manufacturerName: spec?['manufacturerName'] as String?,
      originId: spec?['originCountryId'] as String?,
      originName: spec?['originName'] as String?,
      precision: spec == null
          ? (gradeCode == null
                ? SpecPrecision.unspecified
                : SpecPrecision.unknownManufacturer)
          : _precision(spec['precision']),
      gradeVerified: spec?['gradeVerified'] as bool? ?? true,
    );
  }

  SpecChoice toChoice() => SpecChoice(
    materialId: materialId,
    gradeId: gradeId,
    originId: originId,
    open: isOpen,
  );
}

/// اختيار المستخدم قبل الحفظ؛ يُرسل للسيرفر بالمعرفات فقط.
class SpecChoice {
  const SpecChoice({
    required this.materialId,
    this.gradeId,
    this.originId,
    this.open = false,
  });

  final String materialId;
  final String? gradeId;
  final String? originId;
  final bool open;

  Json toJson() => {
    'materialId': materialId,
    'gradeId': gradeId,
    'originCountryId': originId,
    'openSpec': open,
  };

  @override
  bool operator ==(Object other) =>
      other is SpecChoice &&
      other.materialId == materialId &&
      other.gradeId == gradeId &&
      other.originId == originId &&
      other.open == open;

  @override
  int get hashCode => Object.hash(materialId, gradeId, originId, open);

  /// وصف الاختيار من القوائم المحملة (قبل الحفظ).
  MaterialSpec describe(ReferenceData refs) {
    final material = refs.material(materialId);
    final grade = gradeId == null ? null : refs.grade(gradeId!);
    final maker = grade?.manufacturerId == null
        ? null
        : refs.manufacturer(grade!.manufacturerId!);
    return MaterialSpec(
      materialId: materialId,
      materialCode: material?.code ?? '?',
      gradeId: gradeId,
      gradeCode: grade?.code,
      manufacturerId: maker?.id,
      manufacturerName: maker?.name,
      originId: originId,
      originName: originId == null ? null : refs.country(originId!)?.nameAr,
      precision: open
          ? SpecPrecision.open
          : grade == null
          ? SpecPrecision.unspecified
          : maker == null
          ? SpecPrecision.unknownManufacturer
          : SpecPrecision.exact,
      gradeVerified: grade?.verified ?? true,
    );
  }
}
