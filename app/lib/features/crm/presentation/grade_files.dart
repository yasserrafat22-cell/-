import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/file_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import 'crm_widgets.dart';

/// صورة الـ Grade (دائرة «+») وملف المواصفات (PDF فقط) من الكتالوج الموحد.
/// الإضافة الأولى لأي مستخدم يسجل بيانات؛ الاستبدال والحذف للمدير العام.
class GradeFilesBar extends ConsumerWidget {
  const GradeFilesBar({
    super.key,
    required this.gradeId,
    required this.photoFileId,
    required this.dataSheetFileId,
    this.onChanged,
  });

  final String gradeId;
  final String? photoFileId;
  final String? dataSheetFileId;
  final VoidCallback? onChanged;

  Future<void> _upload(BuildContext context, WidgetRef ref, String kind) async {
    final files = ref.read(fileServicesProvider);
    PickedFile? file;
    if (kind == 'dataSheet') {
      file = await files.pickDocument(const ['pdf']);
    } else {
      final camera = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('الكاميرا'),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                key: const Key('gradeFile.gallery'),
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('المعرض'),
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      );
      if (camera == null) return;
      file = await files.pickImage(camera: camera);
    }
    if (file == null || !context.mounted) return;
    if (kind == 'dataSheet' && !file.name.toLowerCase().endsWith('.pdf')) {
      showErrorSnack(context, 'ملف المواصفات يجب أن يكون PDF فقط');
      return;
    }
    try {
      await ref
          .read(crmRepositoryProvider)
          .uploadGradeFile(
            gradeId: gradeId,
            id: const Uuid().v7(),
            kind: kind,
            filePath: file.path,
            fileName: file.name,
          );
      ref.invalidate(referenceDataProvider);
      onChanged?.call();
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
  }

  Future<void> _openPdf(BuildContext context, WidgetRef ref, String id) async {
    try {
      final bytes = await ref.read(gradeFileBytesProvider(id).future);
      final files = ref.read(fileServicesProvider);
      final path = await files.writeTemp(id, 'datasheet.pdf', bytes);
      final opened = await files.open(path, 'application/pdf');
      if (!opened && context.mounted) {
        showErrorSnack(context, 'لا يوجد تطبيق لعرض ملفات PDF');
      }
    } on ApiException catch (e) {
      if (context.mounted) showErrorSnack(context, e.message);
    }
  }

  /// للمدير: استبدال الملف أو حذفه.
  Future<void> _manage(
    BuildContext context,
    WidgetRef ref,
    String kind,
    String id,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == 'dataSheet')
              ListTile(
                leading: const Icon(Icons.visibility_rounded),
                title: const Text('عرض'),
                onTap: () => Navigator.pop(context, 'open'),
              ),
            ListTile(
              key: const Key('gradeFile.replace'),
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('استبدال'),
              onTap: () => Navigator.pop(context, 'replace'),
            ),
            ListTile(
              key: const Key('gradeFile.delete'),
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text('حذف'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'open':
        await _openPdf(context, ref, id);
      case 'replace':
        await _upload(context, ref, kind);
      case 'delete':
        try {
          await ref.read(crmRepositoryProvider).removeGradeFile(id);
          ref.invalidate(referenceDataProvider);
          onChanged?.call();
        } on ApiException catch (e) {
          if (context.mounted) showErrorSnack(context, e.message);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(canManageProvider);
    final photo = photoFileId == null
        ? null
        : ref.watch(gradeFileBytesProvider(photoFileId!)).value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: photoFileId == null ? 'إضافة صورة' : 'صورة الـ Grade',
          child: InkWell(
            key: Key('gradeFile.photo.$gradeId'),
            customBorder: const CircleBorder(),
            onTap: photoFileId == null
                ? () => _upload(context, ref, 'photo')
                : admin
                ? () => _manage(context, ref, 'photo', photoFileId!)
                : null,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.fieldFill,
              backgroundImage: photo == null ? null : MemoryImage(photo),
              child: photoFileId == null
                  ? const Icon(Icons.add_rounded, color: AppColors.primary)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        TextButton.icon(
          key: Key('gradeFile.sheet.$gradeId'),
          onPressed: dataSheetFileId == null
              ? () => _upload(context, ref, 'dataSheet')
              : admin
              ? () => _manage(context, ref, 'dataSheet', dataSheetFileId!)
              : () => _openPdf(context, ref, dataSheetFileId!),
          icon: Icon(
            dataSheetFileId == null
                ? Icons.note_add_outlined
                : Icons.picture_as_pdf_rounded,
            color: AppColors.error,
          ),
          label: Text(dataSheetFileId == null ? '+ Datasheet' : 'Datasheet'),
        ),
      ],
    );
  }
}
