import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/features/crm/domain/crm_models.dart';
import 'package:qadisiyah/features/crm/domain/phone_rules.dart';
import 'package:qadisiyah/features/crm/domain/quick_entry.dart';

/// حالات «الإدخال السريع» 0.7.0 المشتركة مع السيرفر (`testdata/quick_entry`).
///
/// - سلامة الملفات تُختبر دائمًا.
/// - السلوك المستهدف لكل مرحلة مُتخطى حتى تُنفذ مرحلته، ويُشغَّل يدويًا بـ
///   `QE_TARGET=phase2 flutter test test/features/crm/quick_entry_fixtures_test.dart`
///   (أو `QE_TARGET=all`) لقياس الفجوة. عند تنفيذ المرحلة يُزال تخطيها هنا.
typedef J = Map<String, dynamic>;

final _dir = Directory('../testdata/quick_entry');

J _load(String name) =>
    jsonDecode(File('${_dir.path}/$name').readAsStringSync()) as J;

List<J> _list(Object? value) => (value as List).cast<J>();

String? _s(J map, String key) => map[key] as String?;

final _enabled = (Platform.environment['QE_TARGET'] ?? '')
    .split(',')
    .map((s) => s.trim())
    .toSet();

/// تخطي السلوك المستهدف حتى تُنفذ المرحلة.
Object _until(String phase) =>
    _enabled.contains('all') || _enabled.contains(phase)
    ? false
    : 'السلوك المستهدف لـ $phase (QE_TARGET=$phase لتشغيله)';

/// كتالوج الحالات بنماذج التطبيق.
ReferenceData _reference(J catalog) => ReferenceData(
  activityTypes: const [],
  contactOutcomes: const [],
  governorates: const [],
  currencies: const [],
  units: const [],
  representatives: const [],
  manufacturers: [
    for (final m in _list(catalog['manufacturers']))
      ManufacturerItem(id: _s(m, 'id')!, name: _s(m, 'name')!),
  ],
  countries: [
    for (final c in _list(catalog['countries']))
      LookupItem(
        id: _s(c, 'id')!,
        code: _s(c, 'code')!,
        nameAr: _s(c, 'nameAr')!,
      ),
  ],
  materials: [
    for (final m in _list(catalog['materials']))
      MaterialItem(
        id: _s(m, 'id')!,
        code: _s(m, 'code')!,
        nameAr: _s(m, 'nameAr')!,
        grades: [
          for (final g in _list(m['grades']))
            GradeItem(
              id: _s(g, 'id')!,
              code: _s(g, 'code')!,
              manufacturerId: _s(g, 'manufacturerId'),
              verified: g['verified'] as bool? ?? true,
            ),
        ],
      ),
  ],
);

const _fields = ['name', 'phone', 'material', 'grade', 'manufacturer'];

/// ناتج التحليل الحالي بصيغة الحالات. تستبدله المرحلة 2 بالمحلل الجديد.
List<Map<String, String?>> _parse(String text, ReferenceData refs) {
  final p = parsePaste(text, refs);
  var n = 0;
  final rows = rowsFrom(p.cells, p.mapping, newId: () => '${n++}');
  String? code(String? material) {
    if (material == null) return null;
    final key = material.toLowerCase().replaceAll(RegExp(r'[\s\-_./]'), '');
    return refs.materials
        .where((m) => m.code.toLowerCase() == key)
        .firstOrNull
        ?.code;
  }

  return [
    for (final r in rows)
      {
        'name': r.name,
        'phone': r.phone == null ? null : normalizeMobile(r.phone!),
        'material': code(r.material),
        'grade': r.grade,
        'manufacturer': r.manufacturer,
      },
  ];
}

void main() {
  final catalog = _load('catalog.json');
  final paste = _list(_load('paste_cases.json')['cases']);
  final validation = _list(_load('validation_cases.json')['cases']);
  final phones = _list(_load('phone_cases.json')['cases']);
  final excel = _list(_load('excel_cases.json')['cases']);
  final cleanup = _load('cleanup_cases.json');

  final materials = _list(catalog['materials']);
  final materialIds = {for (final m in materials) _s(m, 'id')};
  final materialCodes = {for (final m in materials) _s(m, 'code')};
  final grades = [for (final m in materials) ..._list(m['grades'])];
  final gradeIds = {for (final g in grades) _s(g, 'id')};
  final makerIds = {
    for (final m in _list(catalog['manufacturers'])) _s(m, 'id'),
  };

  group('fixture integrity', () {
    test('every case file has unique ids', () {
      for (final cases in [paste, validation, excel]) {
        final ids = [for (final c in cases) _s(c, 'id')];
        expect(ids.toSet().length, ids.length);
      }
      final cleanupIds = [
        for (final k in ['eligibility', 'rbac'])
          for (final c in _list(cleanup[k])) _s(c, 'id'),
      ];
      expect(cleanupIds.toSet().length, cleanupIds.length);
    });

    test('catalog references are consistent', () {
      for (final g in grades) {
        if (_s(g, 'manufacturerId') case final String maker) {
          expect(makerIds, contains(maker));
        }
      }
      // 668 غير موجود عمدًا، و TR144 مسجل لشركتين تحت HDPE.
      final codes = [for (final g in grades) _s(g, 'code')];
      expect(codes, isNot(contains('668')));
      expect(codes.where((c) => c == 'TR144').length, 2);
    });

    test('paste expectations use catalog materials and valid phones', () {
      for (final c in paste) {
        final id = _s(c, 'id');
        final expected = _list(c['expected']);
        expect(expected, isNotEmpty, reason: id);
        for (final r in expected) {
          if (_s(r, 'material') case final String material) {
            expect(materialCodes, contains(material), reason: id);
          }
          if (_s(r, 'phone') case final String phone) {
            expect(egyptianMobile.hasMatch(phone), isTrue, reason: id);
          }
        }
      }
    });

    test('validation expectations reference catalog ids', () {
      const statuses = {'ready', 'incomplete', 'needs_review'};
      for (final c in validation) {
        final id = _s(c, 'id');
        final e = c['expected'] as J;
        expect(statuses, contains(_s(e, 'status')), reason: id);
        expect(
          (e['blocking'] as List).isEmpty,
          _s(e, 'status') != 'incomplete',
          reason: '$id: incomplete ⇔ blocking issues',
        );
        if (_s(e, 'materialId') case final String m) {
          expect(materialIds, contains(m), reason: id);
        }
        if (_s(e, 'gradeId') case final String g) {
          expect(gradeIds, contains(g), reason: id);
        }
      }
    });

    test('excel expectations match their sheets', () {
      for (final c in excel) {
        final id = _s(c, 'id');
        final sheets = _list(c['sheets']);
        final expected = _list(c['expected']);
        expect(expected.length, sheets.length, reason: id);
        for (final (i, e) in expected.indexed) {
          final rows = sheets[i]['rows'] as List;
          final header = e['headerRow'] as int;
          expect(rows[header - 1], isNotNull, reason: id);
          for (final r in (e['sourceRows'] as List).cast<int>()) {
            expect(r, greaterThan(header), reason: id);
            expect(rows[r - 1], isNotNull, reason: '$id row $r');
          }
        }
      }
    });
  });

  final refs = _reference(catalog);

  group('target: phone normalization matches the server (phase2)', () {
    for (final c in phones) {
      test(_s(c, 'input')!, () {
        final local = normalizeMobile(_s(c, 'input')!);
        expect(egyptianMobile.hasMatch(local) ? local : null, _s(c, 'local'));
      }, skip: _until('phase2'));
    }
  });

  group('target: free-text parser (phase2)', () {
    for (final c in paste) {
      test('${_s(c, 'id')} ${_s(c, 'description')}', () {
        final actual = _parse(_s(c, 'text')!, refs);
        final expected = _list(c['expected']);
        expect(actual.length, expected.length, reason: 'عدد السجلات');
        for (final (i, e) in expected.indexed) {
          for (final f in _fields) {
            expect(actual[i][f], _s(e, f), reason: 'السجل ${i + 1}: $f');
          }
        }
      }, skip: _until('phase2'));
    }
  });

  group('target: local row validation (phase2, mirrors phase1 server)', () {
    for (final c in validation) {
      test('${_s(c, 'id')} ${_s(c, 'description')}', () {
        final r = c['row'] as J;
        final check = checkRow(
          EntryRow(
            id: _s(c, 'id')!,
            row: 1,
            kind: _s(r, 'kind'),
            name: _s(r, 'name'),
            phone: _s(r, 'phone'),
            material: _s(r, 'material'),
            grade: _s(r, 'grade'),
            manufacturer: _s(r, 'manufacturer'),
          ),
          _s(c, 'audience')!,
          refs,
        );
        final e = c['expected'] as J;
        expect(
          check.issues.toSet(),
          (e['blocking'] as List).cast<String>().toSet(),
          reason: 'blocking',
        );
        expect(check.material?.id, _s(e, 'materialId'), reason: 'material');
        expect(check.grade?.id, _s(e, 'gradeId'), reason: 'grade');
      }, skip: _until('phase2'));
    }
  });
}
