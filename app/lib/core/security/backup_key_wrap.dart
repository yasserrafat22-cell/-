import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart';

/// استلام النسخة الكاملة دون إرسال كلمة المرور للسيرفر:
/// 1. التطبيق يولد مفتاح ECDH P-256 مؤقتًا ويرسل الجزء العام فقط.
/// 2. السيرفر يشفر النسخة بمفتاح عشوائي ويغلفه لهذا المفتاح (صيغة QBKW).
/// 3. التطبيق يفك المفتاح ويعيد تغليفه بكلمة مرور المدير على الجهاز (صيغة QBK2)،
///    دون فك محتوى النسخة نفسها. كلمة المرور لا تغادر الجهاز ولا تُحفظ.
class BackupKeyWrap {
  BackupKeyWrap._(this._private, this.publicKey);

  factory BackupKeyWrap.generate() {
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(
            List.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), random));
    final pair = generator.generateKeyPair();
    return BackupKeyWrap._(pair.privateKey, pair.publicKey.Q!.getEncoded(false));
  }

  /// مفتاح ثابت معروف (للاختبارات المشتركة مع السيرفر فقط).
  @visibleForTesting
  factory BackupKeyWrap.fromPrivate(BigInt d) {
    final q = (_curve.G * d)!;
    return BackupKeyWrap._(ECPrivateKey(d, _curve), q.getEncoded(false));
  }

  static final _curve = ECDomainParameters('prime256v1');
  static final _wire = ascii.encode('QBKW');
  static final _file = ascii.encode('QBK2');
  static final _label = ascii.encode('QBK-WRAP-1');
  static const _pubSize = 65;
  static const _headerSize = 4 + _pubSize + 12 + 32 + 16;

  /// عدد دورات اشتقاق مفتاح كلمة المرور (مخزن في الملف، فيمكن تغييره لاحقًا).
  static const iterations = 310000;

  final ECPrivateKey _private;

  /// نقطة P-256 غير مضغوطة (65 بايت) تُرسل للسيرفر.
  final Uint8List publicKey;

  String get publicKeyBase64 => base64Encode(publicKey);

  /// يحول استجابة السيرفر (QBKW) إلى ملف محفوظ (QBK2) محمي بكلمة المرور.
  Future<Uint8List> toPasswordFile(
    Uint8List wire,
    String password, {
    int rounds = iterations,
  }) async {
    if (wire.length < _headerSize || !_same(wire.sublist(0, 4), _wire)) {
      throw const FormatException('استجابة النسخة غير صالحة');
    }
    final serverPoint = _curve.curve.decodePoint(
      wire.sublist(4, 4 + _pubSize),
    )!;
    final shared = (ECDHBasicAgreement()..init(_private)).calculateAgreement(
      ECPublicKey(serverPoint, _curve),
    );
    final kek = SHA256Digest().process(
      Uint8List.fromList([..._bigIntBytes(shared, 32), ..._label]),
    );
    final aes = c.AesGcm.with256bits();
    final List<int> dataKey;
    try {
      dataKey = await aes.decrypt(
        c.SecretBox(
          wire.sublist(4 + _pubSize + 12, 4 + _pubSize + 44),
          nonce: wire.sublist(4 + _pubSize, 4 + _pubSize + 12),
          mac: c.Mac(wire.sublist(4 + _pubSize + 44, _headerSize)),
        ),
        secretKey: c.SecretKey(kek),
        aad: _wire,
      );
    } on c.SecretBoxAuthenticationError {
      throw const FormatException('تعذر فك مفتاح النسخة على هذا الجهاز');
    }

    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final passwordKey = await c.Pbkdf2(
      macAlgorithm: c.Hmac.sha256(),
      iterations: rounds,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final wrapped = await aes.encrypt(
      dataKey,
      secretKey: passwordKey,
      nonce: aes.newNonce(),
      aad: _file,
    );
    final head = ByteData(8)
      ..setUint8(0, _file[0])
      ..setUint8(1, _file[1])
      ..setUint8(2, _file[2])
      ..setUint8(3, _file[3])
      ..setInt32(4, rounds);
    return Uint8List.fromList([
      ...head.buffer.asUint8List(),
      ...salt,
      ...wrapped.nonce,
      ...wrapped.cipherText,
      ...wrapped.mac.bytes,
      ...wire.sublist(_headerSize),
    ]);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<int> _bigIntBytes(BigInt value, int length) {
    final out = List<int>.filled(length, 0);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }
}
