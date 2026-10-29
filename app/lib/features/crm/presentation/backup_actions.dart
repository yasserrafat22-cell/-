import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/file_services.dart';
import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../application/crm_providers.dart';
import '../application/sync_controller.dart';
import '../domain/crm_format.dart';
import 'crm_widgets.dart';

const minBackupPassword = 10;

/// كلمة مرور لكل نسخة: لا تُحفظ في التطبيق ولا على السيرفر؛ بدونها لا تُفتح النسخة.
Future<String?> askBackupPassword(
  BuildContext context, {
  required String title,
  bool confirm = true,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordDialog(title: title, confirm: confirm),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.confirm});

  final String title;
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _again = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.confirm)
            const Text(
              'احفظ كلمة المرور في مكان آمن؛ لا يمكن فتح النسخة بدونها ولا استرجاعها.',
            ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('backup.password'),
            controller: _password,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: formDecoration(hint: 'كلمة مرور النسخة'),
            validator: (v) =>
                widget.confirm && (v ?? '').length < minBackupPassword
                ? 'على الأقل $minBackupPassword أحرف'
                : (v ?? '').isEmpty
                ? 'أدخل كلمة المرور'
                : null,
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('backup.passwordAgain'),
              controller: _again,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: formDecoration(hint: 'تأكيد كلمة المرور'),
              validator: (v) =>
                  v != _password.text ? 'كلمتا المرور غير متطابقتين' : null,
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const Key('backup.confirm'),
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _password.text);
          }
        },
        child: const Text('متابعة'),
      ),
    ],
  );
}

Future<void> _shareFile(
  WidgetRef ref,
  List<int> bytes,
  String fileName,
  String mimeType,
) async {
  final path = await ref
      .read(fileServicesProvider)
      .writeTemp('export', fileName, Uint8List.fromList(bytes));
  await ref.read(shareServiceProvider).file(path, mimeType: mimeType);
}

/// يشارك ملف Excel (قالب أو تصدير) من قائمة المشاركة.
Future<void> shareExcel(WidgetRef ref, List<int> bytes, String fileName) =>
    _shareFile(
      ref,
      bytes,
      fileName,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

String _stamp(DateTime d) =>
    '${CrmFormat.isoDay(d)}-${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';

/// «حفظ نسخة»: نسخة كاملة مشفرة (قاعدة البيانات + الملفات) للمدير العام، تُحفظ
/// من قائمة المشاركة على الفلاشة أو Drive أو الكمبيوتر.
Future<void> saveFullBackup(BuildContext context, WidgetRef ref) async {
  final password = await askBackupPassword(
    context,
    title: 'نسخة احتياطية كاملة',
  );
  if (password == null || !context.mounted) return;
  showSuccessSnack(context, 'جارٍ تجهيز النسخة الكاملة...');
  try {
    final bytes = await ref.read(crmRepositoryProvider).fullBackup(password);
    await _shareFile(
      ref,
      bytes,
      'qadisiyah-${_stamp(ref.read(clockProvider)())}.qbk',
      'application/octet-stream',
    );
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

/// تصدير العملاء أو الموردين الظاهرين للمستخدم إلى Excel.
Future<void> exportToExcel(
  BuildContext context,
  WidgetRef ref,
  String role,
) async {
  try {
    final bytes = await ref.read(crmRepositoryProvider).exportParties(role);
    await _shareFile(
      ref,
      bytes,
      '${role == 'supplier' ? 'الموردون' : 'العملاء'}-${CrmFormat.isoDay(ref.read(clockProvider)())}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

/// نسخة من بيانات الجهاز غير المرسلة (تعمل دون اتصال).
Future<void> saveDeviceBackup(BuildContext context, WidgetRef ref) async {
  final password = await askBackupPassword(
    context,
    title: 'نسخة من بيانات الجهاز',
  );
  if (password == null || !context.mounted) return;
  try {
    final bytes = await ref.read(crmRepositoryProvider).deviceBackup(password);
    await _shareFile(
      ref,
      bytes,
      'qadisiyah-device-${_stamp(ref.read(clockProvider)())}.qdv',
      'application/octet-stream',
    );
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}

/// استرجاع نسخة بيانات الجهاز (مثلًا بعد تغيير الهاتف) ثم مزامنتها.
Future<void> importDeviceBackup(BuildContext context, WidgetRef ref) async {
  final bytes = await ref.read(fileServicesProvider).pickAnyBytes();
  if (bytes == null || !context.mounted) return;
  final password = await askBackupPassword(
    context,
    title: 'كلمة مرور النسخة',
    confirm: false,
  );
  if (password == null || !context.mounted) return;
  try {
    final added = await ref
        .read(crmRepositoryProvider)
        .importDeviceBackup(bytes, password);
    if (!context.mounted) return;
    showSuccessSnack(context, 'أُضيفت $added عملية للمزامنة');
    await ref.read(syncControllerProvider.notifier).syncNow(quiet: true);
  } on FormatException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e.message);
  }
}
