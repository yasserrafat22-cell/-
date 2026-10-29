import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// قائمة المشاركة في Android (واتساب وغيره). المستخدم يختار التطبيق والمستلم
/// بنفسه؛ لا يُرسل شيء تلقائيًا.
class ShareService {
  const ShareService();

  Future<void> text(String text, {String? subject}) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));

  Future<void> file(String path, {String? mimeType, String? text}) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: mimeType)],
          text: text,
        ),
      );
}

final shareServiceProvider = Provider<ShareService>(
  (ref) => const ShareService(),
);
