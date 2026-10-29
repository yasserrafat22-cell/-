import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/secure_store.dart';

/// حالة عملية محفوظة على الجهاز ولم تصل للسيرفر بعد.
enum PendingStatus {
  /// بانتظار المزامنة (لا يوجد اتصال أو لم تُرسل بعد).
  pending,

  /// رفضها السيرفر (صلاحية، تكرار، تعارض...) وتحتاج قرار المستخدم.
  needsReview,
}

/// عملية كتابة محفوظة محليًا. المعرف داخل المحتوى يولده التطبيق، فإعادة
/// إرسالها لا تكرر البيانات على السيرفر.
class PendingOp {
  PendingOp({
    required this.id,
    required this.userId,
    required this.method,
    required this.path,
    required this.body,
    required this.label,
    required this.createdAt,
    this.partyId,
    this.kind,
    this.status = PendingStatus.pending,
    this.error,
    this.attempts = 0,
  });

  final String id;
  final String userId;
  final String method;
  final String path;
  final Object? body;
  final String label;
  final DateTime createdAt;
  final String? partyId;

  /// نوع العملية (مثل `party.create`) لعرض السجل المحلي قبل المزامنة.
  final String? kind;
  PendingStatus status;
  String? error;
  int attempts;

  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'method': method,
    'path': path,
    'body': body,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    'partyId': partyId,
    'kind': kind,
    'status': status.name,
    'error': error,
    'attempts': attempts,
  };

  factory PendingOp.fromJson(Map<String, Object?> j) => PendingOp(
    id: j['id']! as String,
    userId: j['userId']! as String,
    method: j['method']! as String,
    path: j['path']! as String,
    body: j['body'],
    label: j['label']! as String,
    createdAt: DateTime.parse(j['createdAt']! as String),
    partyId: j['partyId'] as String?,
    kind: j['kind'] as String?,
    status: PendingStatus.values.byName(j['status']! as String),
    error: j['error'] as String?,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
  );
}

/// قراءة وكتابة الملف المشفر (يُستبدل في الاختبارات بذاكرة).
abstract interface class BlobStorage {
  Future<Uint8List?> read();
  Future<void> write(Uint8List bytes);
}

/// ملف داخل مساحة التطبيق الخاصة (لا تصل إليه تطبيقات أخرى).
class FileBlobStorage implements BlobStorage {
  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/offline.bin');

  @override
  Future<Uint8List?> read() async {
    final file = await _file();
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    // استبدال ذري: انقطاع الكهرباء أثناء الحفظ لا يفسد النسخة السابقة.
    await temp.rename(file.path);
  }
}

class MemoryBlobStorage implements BlobStorage {
  Uint8List? bytes;

  @override
  Future<Uint8List?> read() async => bytes;

  @override
  Future<void> write(Uint8List value) async => bytes = value;
}

/// قاعدة بيانات محلية مشفرة (AES-256-GCM). المفتاح عشوائي ومحفوظ في
/// [SecureStore] (Android Keystore)، والمحتوى: نسخ آخر البيانات المعروضة
/// (للعرض دون اتصال) وطابور العمليات غير المرسلة. كل بيانات مستخدم منفصلة.
class OfflineStore {
  OfflineStore({required this._keys, BlobStorage? storage})
    : _storage = storage ?? FileBlobStorage();

  static const _keyName = 'offline.key';
  static final _cipher = AesGcm.with256bits();

  final SecureStore _keys;
  final BlobStorage _storage;
  final _changes = StreamController<void>.broadcast();

  Map<String, Object?> _cache = {};
  List<PendingOp> _ops = [];
  Future<void>? _loading;
  Future<void> _saving = Future.value();

  /// يُطلق عند تغير الطابور (لتحديث العدادات والحالات).
  Stream<void> get changes => _changes.stream;

  Future<SecretKey> _key() async {
    final saved = await _keys.read(_keyName);
    if (saved != null) return SecretKey(base64Decode(saved));
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _keys.write(_keyName, base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  /// تعذر قراءة الملف (لا مسح له في هذه الحالة حتى لا تضيع بيانات محفوظة).
  bool _readFailed = false;

  Future<void> _load() async {
    Uint8List? blob;
    try {
      blob = await _storage.read();
    } on Object {
      _readFailed = true;
      return;
    }
    if (blob == null || blob.length < 28) return;
    try {
      final box = SecretBox.fromConcatenation(
        blob,
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _cipher.decrypt(box, secretKey: await _key());
      final json = jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
      _cache = (json['cache'] as Map?)?.cast<String, Object?>() ?? {};
      _ops = [
        for (final o in (json['ops'] as List? ?? const []))
          PendingOp.fromJson((o as Map).cast<String, Object?>()),
      ];
    } on Object {
      // ملف تالف أو مفتاح مختلف (مثل إعادة تثبيت): لا يُعرض شيء غير صحيح.
      _cache = {};
      _ops = [];
    }
  }

  Future<void> _persist() {
    // حفظ متتابع: لا تتداخل عمليتا كتابة على نفس الملف.
    if (_readFailed) return Future.value();
    return _saving = _saving.then((_) async {
      final clear = utf8.encode(
        jsonEncode({
          'cache': _cache,
          'ops': [for (final o in _ops) o.toJson()],
        }),
      );
      final box = await _cipher.encrypt(clear, secretKey: await _key());
      await _storage.write(box.concatenation());
    });
  }

  // ---------------- نسخة بيانات الجهاز ----------------

  static final _deviceMagic = utf8.encode('QDV1');
  static const _deviceIterations = 120000;

  static Future<SecretKey> _passwordKey(String password, List<int> salt) =>
      Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _deviceIterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);

  /// بيانات المستخدم على الجهاز (العمليات غير المرسلة والنسخ المحلية) مشفرة بكلمة مرور.
  Future<Uint8List> exportFor(String userId, String password) async {
    await _ensureLoaded();
    final prefix = '$userId|';
    final clear = utf8.encode(
      jsonEncode({
        'userId': userId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'ops': [
          for (final o in _ops)
            if (o.userId == userId) o.toJson(),
        ],
        'cache': {
          for (final e in _cache.entries)
            if (e.key.startsWith(prefix)) e.key: e.value,
        },
      }),
    );
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final box = await _cipher.encrypt(
      clear,
      secretKey: await _passwordKey(password, salt),
    );
    return Uint8List.fromList([
      ..._deviceMagic,
      ...salt,
      ...box.concatenation(),
    ]);
  }

  /// يضيف العمليات غير الموجودة فقط (لا تكرار)، لنفس المستخدم فقط. يعيد عدد المضاف.
  Future<int> importFor(String userId, Uint8List bytes, String password) async {
    await _ensureLoaded();
    if (bytes.length < 4 + 16 + 28 ||
        utf8.decode(bytes.sublist(0, 4), allowMalformed: true) != 'QDV1') {
      throw const FormatException('الملف ليس نسخة من بيانات الجهاز');
    }
    final Map<String, Object?> json;
    try {
      final box = SecretBox.fromConcatenation(
        bytes.sublist(20),
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _cipher.decrypt(
        box,
        secretKey: await _passwordKey(password, bytes.sublist(4, 20)),
      );
      json = jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
    } on SecretBoxAuthenticationError {
      throw const FormatException('كلمة المرور غير صحيحة أو الملف تالف');
    }
    if (json['userId'] != userId) {
      throw const FormatException('هذه النسخة لمستخدم آخر');
    }
    var added = 0;
    for (final raw in (json['ops'] as List? ?? const [])) {
      final op = PendingOp.fromJson((raw as Map).cast<String, Object?>());
      if (_ops.any((o) => o.id == op.id)) continue;
      _ops.add(op);
      added++;
    }
    final cache = (json['cache'] as Map?)?.cast<String, Object?>() ?? {};
    for (final e in cache.entries) {
      _cache.putIfAbsent(e.key, () => e.value);
    }
    await _persist();
    _changes.add(null);
    return added;
  }

  // ---------------- النسخ المحلية للعرض دون اتصال ----------------

  Future<Object?> cached(String userId, String path) async {
    await _ensureLoaded();
    return _cache['$userId|$path'];
  }

  Future<void> forget(String userId, String path) async {
    await _ensureLoaded();
    if (_cache.remove('$userId|$path') != null) await _persist();
  }

  Future<void> remember(String userId, String path, Object? json) async {
    await _ensureLoaded();
    _cache['$userId|$path'] = json;
    // حد معقول لحجم النسخ المحلية: الأقدم يُحذف أولًا.
    while (_cache.length > 400) {
      _cache.remove(_cache.keys.first);
    }
    await _persist();
  }

  // ---------------- طابور المزامنة ----------------

  Future<List<PendingOp>> ops(String userId) async {
    await _ensureLoaded();
    return [
      for (final o in _ops)
        if (o.userId == userId) o,
    ];
  }

  Future<void> enqueue(PendingOp op) async {
    await _ensureLoaded();
    if (_ops.any((o) => o.id == op.id)) return;
    _ops.add(op);
    await _persist();
    _changes.add(null);
  }

  Future<void> remove(String opId) async {
    await _ensureLoaded();
    _ops.removeWhere((o) => o.id == opId);
    await _persist();
    _changes.add(null);
  }

  Future<void> update(PendingOp op) async {
    await _ensureLoaded();
    await _persist();
    _changes.add(null);
  }
}
