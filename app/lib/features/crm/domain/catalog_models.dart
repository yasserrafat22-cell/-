import 'crm_models.dart';

/// Grade كما يظهر في كتالوج الإدارة.
class CatalogGrade {
  const CatalogGrade({
    required this.id,
    required this.materialId,
    required this.materialCode,
    required this.code,
    this.manufacturerId,
    this.manufacturerName,
    this.originIds = const [],
    this.description,
    this.verified = true,
    this.active = true,
    this.createdByName,
    this.photoFileId,
    this.dataSheetFileId,
  });

  final String id;
  final String materialId;
  final String materialCode;
  final String code;
  final String? manufacturerId;
  final String? manufacturerName;
  final List<String> originIds;
  final String? description;
  final bool verified;
  final bool active;
  final String? createdByName;
  final String? photoFileId;
  final String? dataSheetFileId;

  factory CatalogGrade.fromJson(Json j) => CatalogGrade(
    id: j['id'] as String,
    materialId: j['materialId'] as String,
    materialCode: j['materialCode'] as String,
    code: j['code'] as String,
    manufacturerId: j['manufacturerId'] as String?,
    manufacturerName: j['manufacturerName'] as String?,
    originIds: (j['originIds'] as List? ?? const []).cast<String>(),
    description: j['description'] as String?,
    verified: j['isVerified'] as bool? ?? true,
    active: j['isActive'] as bool? ?? true,
    createdByName: j['createdByName'] as String?,
    photoFileId: j['photoFileId'] as String?,
    dataSheetFileId: j['dataSheetFileId'] as String?,
  );
}

class CatalogManufacturer {
  const CatalogManufacturer({
    required this.id,
    required this.name,
    this.active = true,
    this.gradeCount = 0,
  });

  final String id;
  final String name;
  final bool active;
  final int gradeCount;

  factory CatalogManufacturer.fromJson(Json j) => CatalogManufacturer(
    id: j['id'] as String,
    name: j['name'] as String,
    active: j['isActive'] as bool? ?? true,
    gradeCount: j['gradeCount'] as int? ?? 0,
  );
}
