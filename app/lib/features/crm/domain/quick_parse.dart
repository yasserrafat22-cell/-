import 'crm_models.dart';
import 'quick_entry.dart' show materialFor, parseKind;
import 'text_rules.dart';

/// اللصق المباشر في «الإدخال السريع».
///
/// - **جدول**: فقط عندما يحتوي كل سطر على Tab (نطاق منسوخ من Excel)؛ يُقترح تعيين الأعمدة
///   ويؤكده المستخدم.
/// - **نص حر** (واتساب أو أي نص، ومنه الأسطر المفصولة بفواصل): سجل لكل جهة، لا لكل سطر.
///   تُفصل السجلات بالأسطر الفارغة، والعناوين المتكررة (الاسم:)، وأرقام الموبايل، والفواصل
///   الواضحة ( - ، | ، ؛). يُستخرج من كل سجل الرقم والخامة والـ Grade والشركة المصنعة والمنشأ
///   والنوع، والباقي اسم. الكمية والسعر لا يُقرآن كـ Grade. لا تعيين أعمدة للنص الحر.
/// - الـ Grade يُستخرج نصًا كما كُتب حتى لو لم يكن في الكتالوج؛ الربط بالكتالوج يقرره
///   التحقق (السيرفر هو المرجع)، والالتباس يرفع أعلام مراجعة.
class PasteParse {
  const PasteParse(
    this.cells,
    this.mapping, {
    required this.free,
    this.flags = const [],
  });

  /// خلايا كل سجل (الجدول: كما في الأعمدة؛ النص الحر: حسب [freeMapping]).
  final List<List<String>> cells;

  /// الحقل ← رقم العمود.
  final Map<String, int> mapping;

  /// نص حر (لا يُعرض تعيين أعمدة).
  final bool free;

  /// أعلام مراجعة لكل سجل في النص الحر: multiple_phones، grade_uncertain،
  /// multiple_grades، split_uncertain.
  final List<List<String>> flags;

  int get columns => cells.fold(0, (m, r) => r.length > m ? r.length : m);
}

/// أعمدة سجلات النص الحر.
const freeMapping = {
  'name': 0,
  'phone': 1,
  'material': 2,
  'grade': 3,
  'manufacturer': 4,
  'origin': 5,
  'kind': 6,
};

/// رقم موبايل مصري داخل نص (بمسافات أو شرطات، و+20/0020/20، أو بلا الصفر الأول).
final mobileInText = RegExp(
  r'(?<![\d+])(?:\+\s?20|0020|20)?[\s\-]?0?1[0125](?:[\s\-]?\d){8}(?!\d)',
);

/// شكل كود Grade: حروف اختيارية ثم 2–5 أرقام ثم حروف اختيارية (668، 5502، 575P، PP500، 218W، TR144).
final _gradeShape = RegExp(
  r'^[a-z]{0,5}-?\d{2,5}[a-z]{0,3}$',
  caseSensitive: false,
);

/// وحدات الكمية والعملات (رقم قبلها ليس Grade).
const _units = {
  'طن',
  'اطنان',
  'كيلو',
  'كجم',
  'كغ',
  'كيلوجرام',
  'جرام',
  'شيكاره',
  'شكاره',
  'شيكارة',
  'شكارة',
  'كيس',
  'اكياس',
  'بالته',
  'باله',
  'جنيه',
  'ج',
  'جم',
  'دولار',
  'ريال',
  'kg',
  'kgs',
  'ton',
  'tons',
  't',
  'mt',
  'bag',
  'bags',
  'egp',
  'le',
  'usd',
  r'$',
  '%',
};

final _numberWithUnit = RegExp(
  r'^\d+(?:[.,]\d+)?(?:kg|kgs|ton|tons|t|mt|%|\$|طن|ك|كجم|كيلو|ج|جم)$',
  caseSensitive: false,
);

/// كلمات تسبق رقم كمية أو سعر.
const _amountWords = {
  'كميه',
  'الكميه',
  'كمية',
  'الكمية',
  'سعر',
  'السعر',
  'بسعر',
  'qty',
  'quantity',
  'price',
  'الاحتياج',
  'احتياج',
  'شهريا',
};

/// عناوين الحقول (مطبّعة) في بطاقات واتساب «الاسم: ...».
final Map<String, String> _labels = {
  for (final e in const {
    'name': [
      'الاسم',
      'اسم',
      'اسم الشركة',
      'الشركة',
      'اسم العميل',
      'اسم المورد',
      'اسم المصنع',
      'name',
      'company',
      'company name',
      'client name',
    ],
    'phone': [
      'موبايل',
      'الموبايل',
      'رقم',
      'الرقم',
      'رقم الموبايل',
      'رقم الهاتف',
      'هاتف',
      'الهاتف',
      'تليفون',
      'التليفون',
      'جوال',
      'واتساب',
      'واتس',
      'mobile',
      'phone',
      'tel',
      'whatsapp',
      'mob',
    ],
    'material': ['الخامة', 'خامة', 'نوع الخامة', 'الخامات', 'material'],
    'grade': ['الجريد', 'جريد', 'الجريدات', 'grade', 'الدرجة', 'درجة'],
    'manufacturer': [
      'الشركة المصنعة',
      'الشركة المنتجة',
      'المصنع',
      'المنتج',
      'manufacturer',
      'maker',
      'brand',
      'producer',
    ],
    'origin': [
      'المنشأ',
      'منشأ',
      'بلد المنشأ',
      'بلد الصنع',
      'المنشا',
      'origin',
      'country',
      'country of origin',
    ],
    'kind': ['النوع', 'نوع السجل', 'type'],
    'skip': [
      'الكمية',
      'كمية',
      'السعر',
      'سعر',
      'ملاحظات',
      'ملاحظة',
      'العنوان',
      'المحافظة',
      'quantity',
      'qty',
      'price',
      'notes',
      'address',
    ],
  }.entries)
    for (final v in e.value) normalizeText(v): e.key,
};

/// كلمات تسبق بلد المنشأ داخل النص.
final _originCues = {
  for (final w in const [
    'منشأ',
    'المنشأ',
    'منشا',
    'صنع',
    'بلد',
    'origin',
    'made',
  ])
    normalizeText(w),
};

/// كلمات النوع (عميل/مورد) كتوكن مستقل.
bool _isKindWord(String core) => parseKind(core) != null;

final _whatsAppPrefix = RegExp(
  r'^\s*(?:\[[^\]]{4,40}\]\s*[^:\n]{1,40}:\s*|\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}(?:\s*[صمapAP]\.?[mM]?\.?)?\s*-\s*[^:\n]{1,40}:\s*)',
);
final _numbering = RegExp(r'^\s*(?:\d{1,3}\s*[\-.)]|[•▪●*]|-)\s+');
final _recordDelimiter = RegExp(r'\s+[-–—|]\s+|\s*[؛;|]\s*');
final _edgePunctuation = RegExp(
  r'^[\s\-–—:،,;؛/|.()\[\]"]+|[\s\-–—:،,;؛/|.()\[\]"]+$',
);
final _innerPunctuation = RegExp(
  r'^[\-–—:،,;؛/|.()\[\]"]+|[\-–—:،,;؛/|.()\[\]"]+$',
);

/// يقسم النص الملصوق إلى سجلات (نص حر) أو جدول (Tab).
PasteParse parsePaste(String text, ReferenceData refs) {
  final lines = latinDigits(text).split(RegExp(r'\r?\n'));
  final filled = [
    for (final l in lines)
      if (l.trim().isNotEmpty) l,
  ];
  if (filled.isEmpty) return const PasteParse([], {}, free: false);

  if (filled.every((l) => l.contains('\t'))) {
    final grid = [
      for (final l in filled) l.split('\t').map((c) => c.trim()).toList(),
    ];
    return PasteParse(grid, suggestMapping(grid, refs), free: false);
  }

  final records = _FreeText(refs).parse(lines);
  return PasteParse(
    [for (final r in records) r.cells],
    freeMapping,
    free: true,
    flags: [for (final r in records) r.flags.toList()],
  );
}

class _Record {
  String? name;
  String? phone;
  String? material;
  String? grade;
  String? manufacturer;
  String? origin;
  String? kind;
  final flags = <String>{};
  final nameParts = <String>[];

  bool get isEmpty =>
      name == null &&
      nameParts.isEmpty &&
      phone == null &&
      material == null &&
      grade == null &&
      manufacturer == null &&
      origin == null;

  List<String> get cells {
    final n =
        name ?? nameParts.join(' ').replaceAll(_edgePunctuation, '').trim();
    return [
      n,
      phone ?? '',
      material ?? '',
      grade ?? '',
      manufacturer ?? '',
      origin ?? '',
      kind ?? '',
    ];
  }
}

enum _T { phone, material, grade, maker, origin, kind, skip, name, punct }

class _Token {
  _Token(this.type, this.value, [this.original = '']);

  final _T type;
  final String value;
  final String original;
}

class _FreeText {
  _FreeText(this.refs);

  final ReferenceData refs;

  List<_Record> parse(List<String> lines) {
    final out = <_Record>[];
    var paragraph = <String>[];
    void flush() {
      if (paragraph.isNotEmpty) out.addAll(_paragraph(paragraph));
      paragraph = [];
    }

    for (final raw in lines) {
      final line = raw
          .replaceFirst(_whatsAppPrefix, '')
          .replaceFirst(_numbering, '')
          .trim();
      if (line.isEmpty) {
        flush();
      } else {
        paragraph.add(line);
      }
    }
    flush();
    return [
      for (final r in out)
        if (!r.isEmpty) r,
    ];
  }

  /// العنوان في أول السطر «الاسم: قيمة» → (الحقل، القيمة)، أو null.
  (String, String)? _label(String line) {
    final m = RegExp(r'^([^:：]{1,30})[:：]\s*(.*)$').firstMatch(line);
    if (m == null) return null;
    final key = normalizeText(m.group(1));
    final field = _labels[key] ?? (_isKindWord(key) ? 'kind:$key' : null);
    return field == null ? null : (field, m.group(2)!.trim());
  }

  List<_Record> _paragraph(List<String> lines) {
    final labelled = lines.any((l) => _label(l) != null);
    if (labelled) return _block(lines);

    // نص بلا عناوين: كل سطر فيه رقم بداية سجل؛ السطر بلا رقم يُلحق بالسجل التالي إن كان
    // فيه اسم (الاسم قبل الرقم)، وإلا بالسابق (خامة/Grade بعد الرقم).
    final phones = [for (final l in lines) mobileInText.allMatches(l).length];
    final chunks = <String>[];
    if (phones.fold(0, (a, b) => a + b) <= 1) {
      chunks.add(lines.join(' '));
    } else {
      final prefix = <String>[];
      for (final (i, l) in lines.indexed) {
        if (phones[i] > 0) {
          chunks.add([...prefix, l].join(' '));
          prefix.clear();
        } else if (_hasName(l) || chunks.isEmpty) {
          prefix.add(l);
        } else {
          chunks[chunks.length - 1] = '${chunks.last} $l';
        }
      }
      if (prefix.isNotEmpty) {
        if (chunks.isEmpty) {
          chunks.add(prefix.join(' '));
        } else {
          chunks[chunks.length - 1] = '${chunks.last} ${prefix.join(' ')}';
        }
      }
    }
    return [for (final c in chunks) ..._chunk(c)];
  }

  /// بطاقات بعناوين: تكرار عنوان الاسم أو الرقم يبدأ سجلًا جديدًا.
  List<_Record> _block(List<String> lines) {
    final out = <_Record>[];
    var cur = _Record();
    for (final l in lines) {
      final label = _label(l);
      if (label == null) {
        _fill(cur, _tokens(l));
        continue;
      }
      final (field, value) = label;
      final repeated = switch (field) {
        'name' => cur.name != null,
        'phone' => cur.phone != null,
        _ => false,
      };
      if (repeated) {
        out.add(cur);
        cur = _Record();
      }
      switch (field) {
        case 'name':
          cur.name = value.replaceAll(_edgePunctuation, '');
        case 'phone':
          final m = mobileInText.firstMatch(value);
          cur.phone = m == null
              ? value
              : (egyptianMobileOrNull(m.group(0)) ?? m.group(0)!.trim());
        case 'material':
          cur.material = materialFor(refs, value)?.code ?? value;
        case 'grade':
          if (value.isNotEmpty) cur.grade = value;
        case 'manufacturer':
          if (value.isNotEmpty) cur.manufacturer = value;
        case 'origin':
          if (value.isNotEmpty) cur.origin = value;
        case 'kind':
          cur.kind = parseKind(value) ?? cur.kind;
        case 'skip':
          break;
        default:
          // «مورد: شركة ...» النوع ثم نص السجل.
          cur.kind = parseKind(field.substring(5));
          _fill(cur, _tokens(value));
      }
    }
    out.add(cur);
    return out;
  }

  bool _hasName(String line) => _tokens(line).any((t) => t.type == _T.name);

  /// سجلات قطعة نص: تقسيم بالفواصل الواضحة ثم بأرقام الموبايل.
  List<_Record> _chunk(String chunk) {
    final parts = chunk.split(_recordDelimiter);
    final delimiters = [
      for (final m in _recordDelimiter.allMatches(chunk)) m.group(0)!,
    ];
    // القطعة بلا رقم تُلحق بما قبلها (أو بما بعدها إن كانت الأولى).
    final segments = <String>[];
    var carry = '';
    for (final (i, p) in parts.indexed) {
      final hasPhone = mobileInText.hasMatch(p);
      if (!hasPhone) {
        if (segments.isEmpty) {
          carry = carry.isEmpty ? p : '$carry${delimiters[i - 1]}$p';
        } else {
          segments[segments.length - 1] =
              '${segments.last}${delimiters[i - 1]}$p';
        }
        continue;
      }
      segments.add(carry.isEmpty ? p : '$carry${delimiters[i - 1]}$p');
      carry = '';
    }
    if (carry.isNotEmpty) segments.add(carry);

    final out = <_Record>[];
    for (final s in segments) {
      final tokens = _tokens(s);
      final phones = tokens.where((t) => t.type == _T.phone).length;
      if (phones <= 1) {
        final r = _Record();
        _fill(r, tokens);
        out.add(r);
        continue;
      }
      // أكثر من رقم دون فاصل: اسم جديد بعد رقم يبدأ سجلًا جديدًا؛ رقمان متجاوران لنفس الجهة.
      final groups = <List<_Token>>[[]];
      var afterPhone = false;
      for (final t in tokens) {
        if (afterPhone && t.type == _T.name) {
          groups.add([]);
          afterPhone = false;
        }
        groups.last.add(t);
        if (t.type == _T.phone) afterPhone = true;
      }
      for (final g in groups) {
        final r = _Record();
        _fill(r, g);
        if (groups.length > 1) r.flags.add('split_uncertain');
        out.add(r);
      }
    }
    return out;
  }

  void _fill(_Record r, List<_Token> tokens) {
    for (final t in tokens) {
      switch (t.type) {
        case _T.phone:
          if (r.phone == null) {
            r.phone = t.value;
          } else if (r.phone != t.value) {
            r.flags.add('multiple_phones');
          }
        case _T.material:
          r.material ??= t.value;
        case _T.grade:
          if (r.grade == null) {
            r.grade = t.value;
            if (RegExp(r'^\d+$').hasMatch(t.value) &&
                _gradeMaterial(t.value) == null &&
                RegExp(r'(00|50)$').hasMatch(t.value)) {
              r.flags.add('grade_uncertain');
            }
            r.material ??= _gradeMaterial(t.value)?.code;
          } else if (normalizeCode(r.grade) != normalizeCode(t.value)) {
            r.flags.add('multiple_grades');
          }
        case _T.maker:
          r.manufacturer ??= t.value;
        case _T.origin:
          r.origin ??= t.value;
        case _T.kind:
          r.kind ??= t.value;
        case _T.skip:
          break;
        case _T.name || _T.punct:
          // الاسم من عنوان «الاسم:» له الأولوية؛ وإلا الكلمات غير المصنفة بترتيبها.
          if (r.name == null) r.nameParts.add(t.original);
      }
    }
  }

  /// خامة الـ Grade في الكتالوج إن كان مسجلًا لخامة واحدة فقط.
  MaterialItem? _gradeMaterial(String code) {
    final key = normalizeCode(code);
    final owners = [
      for (final m in refs.materials)
        if (m.grades.any((g) => normalizeCode(g.code) == key)) m,
    ];
    return owners.length == 1 ? owners.single : null;
  }

  bool _catalogGrade(String core) {
    final key = normalizeCode(core);
    return key.length >= 2 &&
        refs.materials.any(
          (m) => m.grades.any((g) => normalizeCode(g.code) == key),
        );
  }

  String? _maker(String phrase) {
    final n = normalizeText(phrase);
    if (n.isEmpty) return null;
    if (isKnownMakerTerm(n)) return phrase;
    return refs.manufacturers.any((m) => normalizeText(m.name) == n)
        ? phrase
        : null;
  }

  String? _country(String phrase) {
    final n = normalizeText(phrase);
    if (n.length < 3) return null;
    return refs.countries.any((c) => normalizeText(c.nameAr) == n)
        ? phrase
        : null;
  }

  /// توكنات القطعة بأنواعها. العبارات (حتى 4 كلمات) تُطابق أولًا للخامات والشركات والبلدان.
  List<_Token> _tokens(String text) {
    final phones = <String>[];
    final masked = text.replaceAllMapped(mobileInText, (m) {
      phones.add(egyptianMobileOrNull(m.group(0)) ?? m.group(0)!.trim());
      return ' \u0000${phones.length - 1}\u0000 ';
    });
    final words = masked
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final cores = [for (final w in words) w.replaceAll(_innerPunctuation, '')];
    final out = <_Token>[];
    String? hint;
    var skipNumbers = 0;
    var originCue = false;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final core = cores[i];
      if (core.isEmpty) {
        out.add(_Token(_T.punct, '', w));
        continue;
      }
      final phone = RegExp('^\u0000(\\d+)\u0000\$').firstMatch(core);
      if (phone != null) {
        out.add(_Token(_T.phone, phones[int.parse(phone.group(1)!)], w));
        continue;
      }
      final n = normalizeText(core);

      // عنوان داخل السطر «Grade: 668».
      if (w.endsWith(':') || w.endsWith('：')) {
        final field = _labels[n];
        if (field != null) {
          hint = field;
          if (field == 'skip') skipNumbers = 2;
          continue;
        }
      }
      if (hint != null && hint != 'skip' && hint != 'phone') {
        final h = hint;
        hint = null;
        switch (h) {
          case 'name':
            out.add(_Token(_T.name, core, w));
            continue;
          case 'material':
            out.add(
              _Token(_T.material, materialFor(refs, core)?.code ?? core, w),
            );
            continue;
          case 'grade':
            out.add(_Token(_T.grade, core, w));
            continue;
          case 'manufacturer':
            out.add(_Token(_T.maker, core, w));
            continue;
          case 'origin':
            out.add(_Token(_T.origin, core, w));
            continue;
          case 'kind':
            out.add(_Token(_T.kind, parseKind(core) ?? core, w));
            continue;
        }
      }
      hint = null;

      // الكمية والسعر: كلمة كمية/سعر ثم رقم، أو رقم بوحدة.
      if (_amountWords.contains(n)) {
        skipNumbers = 2;
        out.add(_Token(_T.skip, core, w));
        continue;
      }
      final isNumber = RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(core);
      if (_numberWithUnit.hasMatch(core)) {
        out.add(_Token(_T.skip, core, w));
        continue;
      }
      if (isNumber &&
          i + 1 < words.length &&
          _units.contains(normalizeText(cores[i + 1]))) {
        out.add(_Token(_T.skip, core, w));
        i++;
        continue;
      }
      if (_units.contains(n) && out.isNotEmpty && out.last.type == _T.skip) {
        out.add(_Token(_T.skip, core, w));
        continue;
      }
      if (skipNumbers > 0 && isNumber) {
        skipNumbers--;
        out.add(_Token(_T.skip, core, w));
        continue;
      }
      if (!isNumber) skipNumbers = 0;

      // البلد يُقرأ منشأً فقط بعد كلمة دالة («منشأ السعودية»، «صنع مصر»)، حتى لا تُقرأ
      // أسماء مثل «شركة مصر للتجارة» منشأً.
      if (_originCues.contains(n)) {
        originCue = true;
        out.add(_Token(_T.skip, core, w));
        continue;
      }

      if (_isKindWord(n)) {
        out.add(_Token(_T.kind, parseKind(n)!, w));
        continue;
      }

      // عبارات متعددة الكلمات (الأطول أولًا): خامة، شركة مصنعة، بلد.
      var matched = false;
      for (var len = 4; len >= 1 && !matched; len--) {
        if (i + len > words.length) continue;
        final span = cores.sublist(i, i + len);
        if (span.any((c) => c.isEmpty || c.startsWith('\u0000'))) continue;
        final phrase = span.join(' ');
        final original = words.sublist(i, i + len).join(' ');
        if (!RegExp(r'^\d').hasMatch(phrase)) {
          final material = materialFor(refs, phrase);
          if (material != null && (len > 1 || !_catalogGrade(phrase))) {
            out.add(_Token(_T.material, material.code, original));
            matched = true;
          } else if (_maker(phrase) case final String maker) {
            out.add(_Token(_T.maker, maker, original));
            matched = true;
          } else if (originCue && _country(phrase) != null) {
            out.add(_Token(_T.origin, phrase, original));
            originCue = false;
            matched = true;
          }
        }
        if (matched) i += len - 1;
      }
      if (matched) continue;

      if (_catalogGrade(core) || _gradeShape.hasMatch(core)) {
        out.add(_Token(_T.grade, core, w));
        continue;
      }
      out.add(_Token(_T.name, core, w));
    }
    return out;
  }
}

/// هل القيمة تشبه كود Grade (أو مسجلة في الكتالوج).
bool looksLikeGrade(ReferenceData refs, String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (_gradeShape.hasMatch(v)) return true;
  final key = normalizeCode(v);
  return key.length >= 2 &&
      refs.materials.any(
        (m) => m.grades.any((g) => normalizeCode(g.code) == key),
      );
}

/// تعيين مقترح لجدول Tab من المحتوى: عمود الأرقام = الموبايل، ما يطابق الخامات = الخامة،
/// ما يشبه أكواد Grade = Grade، الشركات المصنعة، البلدان، كلمات عميل/مورد = النوع،
/// وأطول نص = الاسم. أقل من الأغلبية لا يُقترح (يحدده المستخدم).
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
    (v) =>
        mobileInText.hasMatch(latinDigits(v)) &&
        RegExp(r'^[\d\s+\-]+$').hasMatch(latinDigits(v)),
  );
  pick('kind', (v) => parseKind(v) != null);
  pick('material', (v) => materialFor(refs, v) != null);
  pick('grade', (v) => looksLikeGrade(refs, v));
  pick(
    'manufacturer',
    (v) =>
        isKnownMakerTerm(normalizeText(v)) ||
        refs.manufacturers.any(
          (m) => normalizeText(m.name) == normalizeText(v),
        ),
  );
  pick(
    'origin',
    (v) =>
        refs.countries.any((c) => normalizeText(c.nameAr) == normalizeText(v)),
  );
  pick('name', (v) => RegExp(r'[A-Za-z؀-ۿ]').hasMatch(v) && v.length >= 2);
  return map;
}
