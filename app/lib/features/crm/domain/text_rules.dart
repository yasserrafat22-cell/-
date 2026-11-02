/// تطبيع النصوص وأسماء الخامات والشركات بنفس قواعد السيرفر
/// (`TextNormalizer` و`Synonyms` في Qadisiyah.Domain.Common) حتى يتطابق التحقق في
/// التطبيق مع حكم السيرفر.
library;

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

/// توحيد أشكال الحروف العربية وإزالة التشكيل والتطويل وتحويل الأرقام وحالة الحروف
/// وتوحيد المسافات.
String normalizeText(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  final b = StringBuffer();
  for (final r in latinDigits(value).runes) {
    var c = r;
    switch (c) {
      case 0x623 || 0x625 || 0x622 || 0x671: // أ إ آ ٱ
        c = 0x627;
      case 0x629: // ة
        c = 0x647;
      case 0x649: // ى
        c = 0x64A;
      case 0x624: // ؤ
        c = 0x648;
      case 0x626: // ئ
        c = 0x64A;
      case 0x640: // ـ
        continue;
    }
    // التشكيل العربي وعلامات الضم غير المتباعدة.
    if ((c >= 0x64B && c <= 0x65F) ||
        c == 0x670 ||
        (c >= 0x6D6 && c <= 0x6ED) ||
        (c >= 0x300 && c <= 0x36F)) {
      continue;
    }
    final ch = String.fromCharCode(c);
    b.write(RegExp(r'\s').hasMatch(ch) ? ' ' : ch.toLowerCase());
  }
  return b.toString().split(' ').where((s) => s.isNotEmpty).join(' ');
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// كود الخامة أو الـ Grade دون فواصل: «SG-5» و«sg 5» و«SG5» تصبح «sg5».
String normalizeCode(String? value) =>
    normalizeText(value)
        .split('')
        .where((c) => _letterOrDigit.hasMatch(c))
        .join();

Map<String, String> _build(Map<String, List<String>> groups) => {
  for (final g in groups.entries)
    for (final v in g.value) normalizeText(v): g.key,
};

final _makerTerms = _build(const {
  'sabic': ['سابك', 'sabic'],
  'borouge': ['بروج', 'borouge'],
  'sipchem': ['سبكيم', 'sipchem'],
  'tasnee': ['التصنيع', 'تصنيع', 'tasnee'],
  'exxonmobil': ['اكسون', 'اكسون موبيل', 'exxon', 'exxonmobil', 'exxon mobil'],
  'lyondellbasell': [
    'ليونديل',
    'ليونديل باسل',
    'lyondell',
    'lyondellbasell',
    'basell',
  ],
  'dow': ['داو', 'dow'],
  'lg chem': ['ال جي', 'ال جي كيم', 'lg', 'lg chem'],
  'totalenergies': ['توتال', 'total', 'totalenergies'],
  'sinopec': ['سينوبك', 'ساينوبك', 'sinopec'],
  'formosa': ['فورموزا', 'formosa'],
  'braskem': ['براسكم', 'braskem'],
  'reliance': ['ريلاينس', 'reliance'],
  'ineos': ['اينيوس', 'ineos'],
  'lotte': ['لوتي', 'lotte'],
  'chevron phillips': ['شيفرون', 'chevron', 'chevron phillips'],
});

final _materialTerms = _build(const {
  'PP': ['pp', 'بولي بروبلين', 'بولي بروبيلين', 'بروبلين', 'polypropylene'],
  'HDPE': ['hdpe', 'بولي ايثيلين عالي الكثافه', 'high density polyethylene'],
  'LDPE': ['ldpe', 'بولي ايثيلين منخفض الكثافه', 'low density polyethylene'],
  'LLDPE': ['lldpe', 'linear low density polyethylene'],
  'PVC': ['pvc', 'بي في سي', 'بولي فينيل كلورايد', 'polyvinyl chloride'],
  'ABS': ['abs', 'ايه بي اس'],
  'PA': ['pa', 'polyamide', 'بولي اميد', 'نايلون', 'nylon'],
  'PS': ['ps', 'بولي ستيرين', 'polystyrene'],
  'PC': ['pc', 'بولي كربونات', 'polycarbonate'],
  'PET': ['pet', 'بولي ايثيلين تيريفثالات'],
});

/// كل الأسماء المكافئة لاسم شركة (مطبّع)، أو الاسم نفسه.
List<String> makerVariants(String normalized) {
  final canonical = _makerTerms[normalized];
  if (canonical == null) return [normalized];
  return [
    for (final t in _makerTerms.entries)
      if (t.value == canonical) t.key,
  ];
}

/// رمز الخامة لاسم معروف (مطبّع)، أو null.
String? synonymMaterialCode(String normalized) => _materialTerms[normalized];

/// هل الاسم المطبّع اسم شركة مصنّعة معروف في المرادفات.
bool isKnownMakerTerm(String normalized) => _makerTerms.containsKey(normalized);

/// رقم الموبايل المصري بصيغة 01xxxxxxxxx إن كان صحيحًا، وإلا null. نفس قاعدة
/// `PhoneNumber.Normalize` في السيرفر: +20 و0020 و20 بلا علامة، والرقم بلا الصفر
/// الأول (Excel يحذفه)، والأرقام العربية.
String? egyptianMobileOrNull(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final text = latinDigits(input).trim();
  final plus = text.startsWith('+');
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final String e164;
  if (plus) {
    e164 = '+$digits';
  } else if (digits.startsWith('00')) {
    e164 = '+${digits.substring(2)}';
  } else if (digits.startsWith('0')) {
    e164 = '+20${digits.substring(1)}';
  } else if (digits.startsWith('20') && digits.length >= 11) {
    e164 = '+$digits';
  } else {
    e164 = '+20$digits';
  }
  return RegExp(r'^\+201[0125]\d{8}$').hasMatch(e164)
      ? '0${e164.substring(3)}'
      : null;
}
