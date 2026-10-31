import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';

/// نفس شكل JSON الذي يرسله السيرفر فعليًا (SearchCard.Specs و RegistryItem.Specs
/// من نوع SpecInfo بلا materialId)؛ كان يسبب خطأ Null/String في البحث الذكي.
const _specInfo = {
  'materialCode': 'PP',
  'gradeCode': '500P',
  'manufacturerId': '0192f0c0-0000-7000-8000-0000000000aa',
  'manufacturerName': 'SABIC',
  'originCountryId': null,
  'originName': null,
  'openSpec': false,
  'gradeVerified': true,
  'precision': 'exact',
};

void main() {
  test('search results parse the server SpecInfo shape', () {
    final r = SearchResults.fromJson({
      'suggestions': [
        {
          'kind': 'grade',
          'id': '0192f0c0-0000-7000-8000-0000000000bb',
          'label': 'PP · SABIC · 500P',
          'materialId': '0192f0c0-0000-7000-8000-0000000000cc',
          'manufacturerId': null,
        },
      ],
      'suppliers': [],
      'customers': [
        {
          'partyId': '0192f0c0-0000-7000-8000-0000000000dd',
          'name': 'شركة النور',
          'isCustomer': true,
          'isSupplier': false,
          'phone': null,
          'contactName': null,
          'email': null,
          'specs': [_specInfo],
          'reasons': ['يحتاج PP · SABIC · 500P'],
          'exact': true,
          'score': 100,
        },
      ],
    });
    final spec = r.customers.single.specs.single;
    expect(spec.gradeCode, '500P');
    expect(spec.manufacturerName, 'SABIC');
  });
}
