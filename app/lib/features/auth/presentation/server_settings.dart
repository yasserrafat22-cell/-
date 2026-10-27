import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/server_address.dart';
import '../../../core/theme/app_colors.dart';

/// شارة «نسخة تجريبية» أسفل بطاقة الدخول تعرض عنوان السيرفر وتفتح إعداده.
/// تظهر في نسخة التجربة (Debug) فقط.
class TrialServerChip extends ConsumerWidget {
  const TrialServerChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(serverAddressProvider);
    return Center(
      child: ActionChip(
        key: const Key('trial.serverChip'),
        avatar: const Icon(Icons.dns_rounded, size: 18, color: AppColors.navy),
        backgroundColor: const Color(0xFFFFF4E0),
        side: const BorderSide(color: Color(0xFFF5C77A)),
        label: Text(
          'نسخة تجريبية • السيرفر: $url',
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontSize: 12, color: Color(0xFF7A4E00)),
        ),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const ServerSettingsDialog(),
        ),
      ),
    );
  }
}

/// يفحص وصول الهاتف للسيرفر عبر `GET /health`؛ يُستبدل في الاختبارات.
final serverHealthCheckProvider = Provider<Future<bool> Function(String url)>(
  (ref) => _defaultHealthCheck,
);

Future<bool> _defaultHealthCheck(String url) async {
  try {
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    ).get<String>('${AppConfig.normalizeServerUrl(url)}/health');
    return response.statusCode == 200;
  } on DioException {
    return false;
  }
}

/// يحدد عنوان سيرفر التجربة على الشبكة المحلية ويختبر الوصول إليه.
class ServerSettingsDialog extends ConsumerStatefulWidget {
  const ServerSettingsDialog({super.key});

  @override
  ConsumerState<ServerSettingsDialog> createState() =>
      _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends ConsumerState<ServerSettingsDialog> {
  late final _url = TextEditingController(
    text: ref.read(serverAddressProvider),
  );
  String? _error;
  bool? _reachable;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final error = AppConfig.validateServerUrl(_url.text);
    setState(() {
      _error = error;
      _reachable = null;
    });
    if (error != null) return;
    setState(() => _busy = true);
    final ok = await ref.read(serverHealthCheckProvider)(_url.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reachable = ok;
    });
  }

  Future<void> _save() async {
    final error = await ref.read(serverAddressProvider.notifier).set(_url.text);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('عنوان السيرفر التجريبي'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اكتب العنوان الذي ظهر عند تشغيل السيرفر على الكمبيوتر. '
            'يجب أن يكون الهاتف والكمبيوتر على نفس شبكة Wi-Fi.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('trial.serverUrl'),
            controller: _url,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'http://192.168.1.50:5080',
              errorText: _error,
            ),
          ),
          if (_reachable != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _reachable!
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: _reachable! ? AppColors.greenDark : AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _reachable! ? 'السيرفر متصل' : 'تعذر الوصول للسيرفر. تحقق أنه يعمل وأن الهاتف على نفس الشبكة',
                    style: TextStyle(
                      fontSize: 13,
                      color: _reachable!
                          ? AppColors.greenDark
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('trial.testServer'),
          onPressed: _busy ? null : _test,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('اختبار الاتصال'),
        ),
        FilledButton(
          key: const Key('trial.saveServer'),
          onPressed: _busy ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
