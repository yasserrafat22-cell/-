import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// ملف اختاره المستخدم من الهاتف.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

/// اختيار الصور والملفات وفتح الملفات المحفوظة مؤقتًا. منفصل حتى يُستبدل في الاختبارات.
class FileServices {
  const FileServices();

  /// صورة من الكاميرا أو المعرض، مصغرة إلى 2048 بكسل لتقليل الحجم.
  Future<PickedFile?> pickImage({required bool camera}) async {
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (file == null) return null;
    return PickedFile(
      path: file.path,
      name: file.name,
      size: await file.length(),
    );
  }

  /// ملف PDF أو صورة (حسب [extensions]).
  Future<PickedFile?> pickDocument(List<String> extensions) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final path = file?.path;
    if (file == null || path == null) return null;
    return PickedFile(
      path: path,
      name: file.name,
      size: await file.xFile.length(),
    );
  }

  /// أي ملف (مثل نسخة بيانات الجهاز)؛ يُعاد محتواه مباشرة.
  Future<Uint8List?> pickAnyBytes() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    return file == null ? null : await file.xFile.readAsBytes();
  }

  /// يحفظ محتوى ملف مرفق في مجلد مؤقت ليُعرض أو يُشارك.
  Future<String> writeTemp(String id, String fileName, Uint8List bytes) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/attachments/$id',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// يفتح الملف بالتطبيق المناسب في الهاتف (عارض PDF).
  Future<bool> open(String path, String mimeType) async =>
      (await OpenFilex.open(path, type: mimeType)).type == ResultType.done;
}

final fileServicesProvider = Provider<FileServices>(
  (ref) => const FileServices(),
);
