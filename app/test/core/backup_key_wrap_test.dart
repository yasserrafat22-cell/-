import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/security/backup_key_wrap.dart';

/// نفس المفتاح الثابت الذي أنشأ له السيرفر ملف الاختبار backup_wire.bin.
final _device = BackupKeyWrap.fromPrivate(
  BigInt.parse(
    '5c1d1b6a3ae33215c1d1b6a3ae33215c1d1b6a3ae33215c1d1b6a3ae3321',
    radix: 16,
  ),
);
const _plain = 'QADISIYAH BACKUP FIXTURE — نسخة اختبار';

/// فك ملف QBK2 هنا للتحقق (التطبيق نفسه لا يفك النسخ؛ الاستعادة بأداة السيرفر).
Future<String> _open(Uint8List file, String password) async {
  final data = ByteData.sublistView(file);
  final rounds = data.getInt32(4);
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: rounds,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: file.sublist(8, 24));
  final aes = AesGcm.with256bits();
  final dataKey = await aes.decrypt(
    SecretBox(
      file.sublist(36, 68),
      nonce: file.sublist(24, 36),
      mac: Mac(file.sublist(68, 84)),
    ),
    secretKey: key,
    aad: ascii.encode('QBK2'),
  );
  final prefix = file.sublist(84, 88);
  final length = ByteData.sublistView(file, 88, 92).getUint32(0) & 0x7fffffff;
  final plain = await aes.decrypt(
    SecretBox(
      file.sublist(92, 92 + length),
      nonce: [...prefix, 0, 0, 0, 0, 0, 0, 0, 0],
      mac: Mac(file.sublist(92 + length, 108 + length)),
    ),
    secretKey: SecretKey(dataKey),
    aad: [1],
  );
  return utf8.decode(plain);
}

void main() {
  final wire = File('test/fixtures/backup_wire.bin').readAsBytesSync();

  test('only the device key opens the server response, and the password '
      'wraps it on the device', () async {
    final file = await _device.toPasswordFile(
      wire,
      'App-Fixture-Password',
      rounds: 100000,
    );
    expect(ascii.decode(file.sublist(0, 4)), 'QBK2');
    expect(await _open(file, 'App-Fixture-Password'), _plain);
    await expectLater(
      _open(file, 'wrong-password-123'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      BackupKeyWrap.generate().toPasswordFile(wire, 'App-Fixture-Password'),
      throwsA(isA<FormatException>()),
    );
    if (Platform.environment['QBK_WRITE_FIXTURE'] == '1') {
      File('test/fixtures/backup_from_app.qbk2').writeAsBytesSync(file);
    }
  });

  test('the public key sent to the server is a P-256 point only', () {
    final key = BackupKeyWrap.generate();
    expect(key.publicKey.length, 65);
    expect(key.publicKey.first, 4);
  });
}
