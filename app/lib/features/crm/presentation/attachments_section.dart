import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/file_services.dart';
import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_models.dart';
import 'crm_widgets.dart';
import 'material_picker.dart';

const _maxImageBytes = 10 * 1024 * 1024;
const _maxPdfBytes = 20 * 1024 * 1024;

/// قسم «المرفقات»: الشعار، وصور المنتجات، وملفات TDS (للمورد)، ومرفقات أخرى.
/// العرض والمشاركة لكل من يرى السجل؛ الإضافة والحذف لمن يملك التعديل.
class AttachmentsSection extends ConsumerStatefulWidget {
  const AttachmentsSection({
    super.key,
    required this.party,
    required this.supplier,
  });

  final PartyDetail party;
  final bool supplier;

  @override
  ConsumerState<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends ConsumerState<AttachmentsSection> {
  bool _uploading = false;

  PartyDetail get _party => widget.party;

  void _refresh() => refreshParty(ref, _party.id);

  Future<void> _add() async {
    final kinds = [
      // الشعار يُضاف مرة؛ استبداله بعد الحفظ للمدير العام فقط.
      if (_party.logoAttachmentId == null || _party.canEdit)
        AttachmentKind.logo,
      if (widget.supplier) ...[
        AttachmentKind.productPhoto,
        AttachmentKind.technicalDataSheet,
      ],
      AttachmentKind.other,
    ];
    final kind = await showModalBottomSheet<AttachmentKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in kinds)
              ListTile(
                key: Key('attachment.kind.${k.name}'),
                leading: Icon(switch (k) {
                  AttachmentKind.logo => Icons.business_rounded,
                  AttachmentKind.productPhoto => Icons.add_a_photo_outlined,
                  AttachmentKind.technicalDataSheet =>
                    Icons.picture_as_pdf_rounded,
                  AttachmentKind.other => Icons.attach_file_rounded,
                }, color: AppColors.primary),
                title: Text(k.nameAr),
                subtitle: Text(switch (k) {
                  AttachmentKind.technicalDataSheet =>
                    'PDF مرتبط بالخامة والشركة والـ Grade',
                  AttachmentKind.other => 'صورة أو PDF',
                  _ => 'صورة من الكاميرا أو المعرض',
                }),
                onTap: () => Navigator.pop(context, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    final files = ref.read(fileServicesProvider);
    PickedFile? file;
    if (kind == AttachmentKind.technicalDataSheet) {
      file = await files.pickDocument(const ['pdf']);
    } else if (kind == AttachmentKind.other) {
      file = await files.pickDocument(const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp',
      ]);
    } else {
      final camera = await _askSource();
      if (camera == null) return;
      file = await files.pickImage(camera: camera);
    }
    if (file == null || !mounted) return;
    final isPdf = file.name.toLowerCase().endsWith('.pdf');
    if (file.size > (isPdf ? _maxPdfBytes : _maxImageBytes)) {
      showErrorSnack(
        context,
        isPdf ? 'الحد الأقصى لملف PDF هو 20MB' : 'الحد الأقصى للصورة هو 10MB',
      );
      return;
    }

    // ملف TDS يُربط بـ Grade محدد الشركة؛ صورة المنتج يمكن ربطها بخامة.
    SpecChoice? spec;
    if (kind
        case AttachmentKind.technicalDataSheet || AttachmentKind.productPhoto) {
      spec = await _askSpec(
        required: kind == AttachmentKind.technicalDataSheet,
      );
      if (!mounted) return;
      if (kind == AttachmentKind.technicalDataSheet && spec == null) return;
    }

    setState(() => _uploading = true);
    try {
      await ref
          .read(crmRepositoryProvider)
          .uploadAttachment(
            partyId: _party.id,
            id: const Uuid().v7(),
            kind: kind,
            filePath: file.path,
            fileName: file.name,
            gradeId: spec?.gradeId,
            materialId: spec?.materialId,
          );
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool?> _askSource() => showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('attachment.camera'),
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('الكاميرا'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            key: const Key('attachment.gallery'),
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('المعرض'),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    ),
  );

  /// الاختيار من منتجات المورد المحددة، أو Grade آخر من الكتالوج.
  Future<SpecChoice?> _askSpec({required bool required}) async {
    final exact = [
      for (final p in _party.products)
        if (p.spec.precision == SpecPrecision.exact) p.spec,
    ];
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                required
                    ? 'اختر الخامة والشركة والـ Grade لهذا الملف'
                    : 'ربط الصورة بمنتج (اختياري)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final s in exact)
              ListTile(
                key: Key('attachment.spec.${s.gradeId}'),
                title: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SpecChip(s),
                ),
                onTap: () => Navigator.pop(context, s.toChoice()),
              ),
            ListTile(
              key: const Key('attachment.otherGrade'),
              leading: const Icon(Icons.search_rounded),
              title: const Text('Grade آخر من الكتالوج'),
              onTap: () => Navigator.pop(context, 'other'),
            ),
            if (!required)
              ListTile(
                key: const Key('attachment.noSpec'),
                leading: const Icon(Icons.block_rounded),
                title: const Text('بدون ربط'),
                onTap: () => Navigator.pop(context, 'none'),
              ),
          ],
        ),
      ),
    );
    if (picked is SpecChoice) return picked;
    if (picked == 'none' || picked == null || !mounted) return null;
    final choice = await pickSpec(context, allowOpen: false);
    if (choice == null || !mounted) return null;
    if (required) {
      final refs = ref.read(referenceDataProvider).value;
      final grade = choice.gradeId == null
          ? null
          : refs?.grade(choice.gradeId!);
      if (grade?.manufacturerId == null) {
        showErrorSnack(
          context,
          'ملف TDS يحتاج Grade محدد الشركة المصنّعة. اختر Grade من شركة معروفة',
        );
        return null;
      }
    }
    return choice;
  }

  @override
  Widget build(BuildContext context) {
    final attachments = ref.watch(attachmentsProvider(_party.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: FieldLabel('المرفقات', icon: Icons.attach_file_rounded),
            ),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_party.canAdd)
              TextButton.icon(
                key: const Key('attachment.add'),
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة'),
              ),
          ],
        ),
        switch (attachments) {
          AsyncData(:final value) => _content(value),
          AsyncError() => TextButton(
            onPressed: () => ref.invalidate(attachmentsProvider(_party.id)),
            child: const Text('تعذر تحميل المرفقات — إعادة المحاولة'),
          ),
          _ => const LinearProgressIndicator(),
        },
      ],
    );
  }

  Widget _content(List<AttachmentItem> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'لا توجد ملفات مرفقة',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    final images = items.where((a) => a.isImage).toList();
    final tds = items
        .where((a) => a.kind == AttachmentKind.technicalDataSheet)
        .toList();
    final otherPdfs = items
        .where((a) => a.isPdf && a.kind != AttachmentKind.technicalDataSheet)
        .toList();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty) ...[
            const Text('الصور', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in images)
                  _Thumbnail(
                    attachment: a,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            _ImageViewer(attachment: a, party: _party),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (tds.isNotEmpty) ...[
            if (images.isNotEmpty) const Divider(height: 22),
            const Text(
              'Technical Data Sheets',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final a in tds) _FileRow(attachment: a, party: _party),
          ],
          if (otherPdfs.isNotEmpty) ...[
            if (images.isNotEmpty || tds.isNotEmpty) const Divider(height: 22),
            const Text(
              'ملفات أخرى',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final a in otherPdfs) _FileRow(attachment: a, party: _party),
          ],
        ],
      ),
    );
  }
}

/// تنزيل المرفق وحفظه مؤقتًا ثم عرضه أو مشاركته.
Future<String?> _localCopy(
  BuildContext context,
  WidgetRef ref,
  AttachmentItem a,
) async {
  try {
    final bytes = await ref.read(attachmentBytesProvider(a.id).future);
    return await ref
        .read(fileServicesProvider)
        .writeTemp(a.id, a.fileName, bytes);
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
    return null;
  }
}

Future<void> _share(
  BuildContext context,
  WidgetRef ref,
  AttachmentItem a,
) async {
  final path = await _localCopy(context, ref, a);
  if (path == null) return;
  await ref
      .read(shareServiceProvider)
      .file(path, mimeType: a.contentType, text: a.spec?.label);
}

Future<void> _remove(
  BuildContext context,
  WidgetRef ref,
  AttachmentItem a,
  PartyDetail party,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('حذف الملف؟'),
      content: Text(a.fileName),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('attachment.confirmDelete'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(crmRepositoryProvider).removeAttachment(a.id);
    refreshParty(ref, party.id);
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.attachment, required this.onTap});

  final AttachmentItem attachment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(attachmentBytesProvider(attachment.id));
    return InkWell(
      key: Key('attachment.image.${attachment.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(10),
          border: attachment.kind == AttachmentKind.logo
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: switch (bytes) {
          AsyncData(:final value) => Image.memory(
            value,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: AppColors.hint),
          ),
          AsyncError() => const Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.hint,
          ),
          _ => const Icon(Icons.image, color: AppColors.primary),
        },
      ),
    );
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({required this.attachment, required this.party});

  final AttachmentItem attachment;
  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = attachment;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.spec case final spec?) SpecChip(spec),
                Text(
                  '${a.fileName} • ${a.sizeLabel}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('attachment.view.${a.id}'),
            tooltip: 'عرض',
            onPressed: () async {
              final path = await _localCopy(context, ref, a);
              if (path == null) return;
              final opened = await ref
                  .read(fileServicesProvider)
                  .open(path, a.contentType);
              if (!opened && context.mounted) {
                showErrorSnack(context, 'لا يوجد تطبيق لعرض هذا الملف');
              }
            },
            icon: const Icon(
              Icons.visibility_rounded,
              color: AppColors.primary,
            ),
          ),
          IconButton(
            key: Key('attachment.share.${a.id}'),
            tooltip: 'مشاركة',
            onPressed: () => _share(context, ref, a),
            icon: const Icon(Icons.share_rounded, color: AppColors.greenDark),
          ),
          if (party.canEdit)
            IconButton(
              key: Key('attachment.delete.${a.id}'),
              tooltip: 'حذف',
              onPressed: () => _remove(context, ref, a, party),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageViewer extends ConsumerWidget {
  const _ImageViewer({required this.attachment, required this.party});

  final AttachmentItem attachment;
  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(attachmentBytesProvider(attachment.id));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          attachment.spec?.label ?? attachment.kind.nameAr,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'مشاركة',
            onPressed: () => _share(context, ref, attachment),
            icon: const Icon(Icons.share_rounded),
          ),
          if (party.canEdit)
            IconButton(
              tooltip: 'حذف',
              onPressed: () async {
                await _remove(context, ref, attachment, party);
                if (context.mounted) Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Center(
        child: switch (bytes) {
          AsyncData(:final value) => InteractiveViewer(
            child: Image.memory(value),
          ),
          AsyncError() => const Text(
            'تعذر تحميل الصورة',
            style: TextStyle(color: Colors.white),
          ),
          _ => const CircularProgressIndicator(),
        },
      ),
    );
  }
}

/// شعار الطرف في رأس الملف، أو الأيقونة الافتراضية.
class PartyAvatar extends ConsumerWidget {
  const PartyAvatar({super.key, required this.party, this.size = 60});

  final PartyDetail party;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = party.logoAttachmentId == null
        ? null
        : ref.watch(attachmentBytesProvider(party.logoAttachmentId!)).value;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: logo == null ? null : Colors.white,
        border: logo == null ? null : Border.all(color: AppColors.fieldBorder),
        gradient: logo == null
            ? const LinearGradient(colors: [AppColors.primary, AppColors.navy])
            : null,
      ),
      child: logo == null
          ? Icon(
              Icons.apartment_rounded,
              color: Colors.white,
              size: size * 0.53,
            )
          : Image.memory(logo, fit: BoxFit.cover),
    );
  }
}
