import 'crm_models.dart';

/// اقتراح من الكتالوج أثناء الكتابة (شركة مصنّعة، خامة، Grade).
class SearchSuggestion {
  const SearchSuggestion({
    required this.kind,
    required this.id,
    required this.label,
    this.materialId,
    this.manufacturerId,
  });

  final String kind;
  final String id;
  final String label;
  final String? materialId;
  final String? manufacturerId;

  factory SearchSuggestion.fromJson(Json j) => SearchSuggestion(
    kind: j['kind'] as String,
    id: j['id'] as String,
    label: j['label'] as String,
    materialId: j['materialId'] as String?,
    manufacturerId: j['manufacturerId'] as String?,
  );
}

/// بطاقة نتيجة: بيانات التواصل المسموح بها وأسباب المطابقة.
class SearchCard {
  const SearchCard({
    required this.partyId,
    required this.name,
    required this.isCustomer,
    required this.isSupplier,
    this.phone,
    this.contactName,
    this.email,
    this.specs = const [],
    this.reasons = const [],
    this.exact = false,
  });

  final String partyId;
  final String name;
  final bool isCustomer;
  final bool isSupplier;
  final String? phone;
  final String? contactName;
  final String? email;
  final List<MaterialSpec> specs;
  final List<String> reasons;
  final bool exact;

  factory SearchCard.fromJson(Json j) => SearchCard(
    partyId: j['partyId'] as String,
    name: j['name'] as String,
    isCustomer: j['isCustomer'] as bool? ?? false,
    isSupplier: j['isSupplier'] as bool? ?? false,
    phone: j['phone'] as String?,
    contactName: j['contactName'] as String?,
    email: j['email'] as String?,
    specs: [
      for (final s in (j['specs'] as List? ?? const []).cast<Json>())
        MaterialSpec.fromJson(s),
    ],
    reasons: (j['reasons'] as List? ?? const []).cast<String>(),
    exact: j['exact'] as bool? ?? false,
  );
}

class SearchResults {
  const SearchResults({
    this.suggestions = const [],
    this.suppliers = const [],
    this.customers = const [],
  });

  final List<SearchSuggestion> suggestions;
  final List<SearchCard> suppliers;
  final List<SearchCard> customers;

  int get total => suppliers.length + customers.length;

  factory SearchResults.fromJson(Json j) => SearchResults(
    suggestions: [
      for (final s in (j['suggestions'] as List).cast<Json>())
        SearchSuggestion.fromJson(s),
    ],
    suppliers: [
      for (final c in (j['suppliers'] as List).cast<Json>())
        SearchCard.fromJson(c),
    ],
    customers: [
      for (final c in (j['customers'] as List).cast<Json>())
        SearchCard.fromJson(c),
    ],
  );
}

/// ما يُبحث عنه: نص حر و/أو اختيار من الاقتراحات.
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.materialId,
    this.manufacturerId,
    this.gradeId,
    this.label,
  });

  final String text;
  final String? materialId;
  final String? manufacturerId;
  final String? gradeId;

  /// وصف الاختيار لعرضه في الشريحة والملفات المصدّرة.
  final String? label;

  bool get isEmpty =>
      text.trim().length < 2 &&
      materialId == null &&
      manufacturerId == null &&
      gradeId == null;

  Map<String, String> toQuery() => {
    if (text.trim().isNotEmpty) 'q': text.trim(),
    'materialId': ?materialId,
    'manufacturerId': ?manufacturerId,
    'gradeId': ?gradeId,
  };

  Json toJson() => {
    'q': text.trim().isEmpty ? null : text.trim(),
    'materialId': materialId,
    'manufacturerId': manufacturerId,
    'gradeId': gradeId,
  };

  String get title => label ?? text.trim();

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.text == text &&
      other.materialId == materialId &&
      other.manufacturerId == manufacturerId &&
      other.gradeId == gradeId;

  @override
  int get hashCode => Object.hash(text, materialId, manufacturerId, gradeId);
}
