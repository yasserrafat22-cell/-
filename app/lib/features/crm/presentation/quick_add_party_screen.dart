import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../data/crm_repository.dart';
import '../domain/crm_models.dart';
import 'contact_launcher.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';
import 'material_picker.dart';

IconData activityIcon(String code) => switch (code) {
  'factory' => Icons.factory_rounded,
  'converter' => Icons.precision_manufacturing_rounded,
  'trader' => Icons.storefront_rounded,
  'distributor' => Icons.hub_rounded,
  'importer' => Icons.directions_boat_filled_rounded,
  _ => Icons.more_horiz_rounded,
};

/// تسجيل سريع لعميل (ص8) أو مورد (ص9) بالبيانات الأساسية فقط؛ العنوان
/// والموقع يُستكملان لاحقًا من الملف (قرار T1).
class QuickAddPartyScreen extends ConsumerStatefulWidget {
  const QuickAddPartyScreen({super.key, required this.isCustomer});

  final bool isCustomer;

  @override
  ConsumerState<QuickAddPartyScreen> createState() =>
      _QuickAddPartyScreenState();
}

class _QuickAddPartyScreenState extends ConsumerState<QuickAddPartyScreen> {
  // معرف ثابت للنموذج: إعادة الحفظ بعد خطأ اتصال لا تنشئ سجلًا مكررًا.
  final _id = const Uuid().v7();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _activityId;
  String? _representativeId;
  final _specs = <SpecChoice>[];
  bool _saving = false;
  bool _showErrors = false;

  bool get _customer => widget.isCustomer;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save(ReferenceData refs) async {
    setState(() => _showErrors = true);
    if (!_formKey.currentState!.validate() ||
        _activityId == null ||
        (_representativeId ?? refs.myRepresentativeId) == null) {
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(crmRepositoryProvider);
    try {
      final party = await repo.createParty(
        NewParty(
          id: _id,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          isCustomer: _customer,
          activityId: _activityId,
          representativeId: _representativeId ?? refs.myRepresentativeId,
          specs: _specs,
        ),
      );
      if (!mounted) return;
      context.pushReplacement(CrmRoutes.party(party.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final duplicate = e.code == 'party.duplicate_phone'
          ? DuplicateParty.fromData(e.data)
          : null;
      if (duplicate != null) {
        await _handleDuplicate(duplicate, e.message);
      } else {
        showErrorSnack(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// الرقم مسجل لشركة أخرى في النظام: لا تكرار؛ يُفتح الملف الموجود، أو
  /// يُضاف الدور الجديد لنفس الشركة إن كانت مسجلة بالدور الآخر.
  Future<void> _handleDuplicate(DuplicateParty existing, String message) async {
    final hasRole = _customer ? existing.isCustomer : existing.isSupplier;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رقم مسجل بالفعل'),
        content: Text(
          hasRole
              ? '$message.\nافتح الملف الموجود بدل تسجيله مرة أخرى.'
              : '$message ك${existing.isCustomer ? 'عميل' : 'مورد'}.\n'
                    'يمكن إضافته ك${_customer ? 'عميل' : 'مورد'} لنفس الشركة دون تكرار.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          if (!hasRole)
            TextButton(
              key: const Key('duplicate.addRole'),
              onPressed: () => Navigator.pop(context, 'role'),
              child: Text('إضافته ك${_customer ? 'عميل' : 'مورد'}'),
            ),
          FilledButton(
            key: const Key('duplicate.open'),
            onPressed: () => Navigator.pop(context, 'open'),
            child: const Text('فتح الملف'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'role') {
      try {
        await ref
            .read(crmRepositoryProvider)
            .addRole(
              existing.partyId,
              customer: _customer,
              activityId: _activityId,
            );
      } on ApiException catch (e) {
        if (mounted) showErrorSnack(context, e.message);
        return;
      }
    }
    if (mounted) context.pushReplacement(CrmRoutes.party(existing.partyId));
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider);
    return CrmScaffold(
      title: _customer ? 'إضافة عميل جديد' : 'إضافة مورد جديد',
      icon: Icons.person_add_alt_1_rounded,
      bottom: refs.hasValue
          ? SaveButton(
              label: _customer ? 'حفظ العميل' : 'حفظ المورد',
              busy: _saving,
              onPressed: () => _save(refs.requireValue),
            )
          : null,
      body: refs.when(
        data: _form,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _LoadError(
          message: e is ApiException ? e.message : 'تعذر تحميل القوائم',
          onRetry: () => ref.invalidate(referenceDataProvider),
        ),
      ),
    );
  }

  Widget _form(ReferenceData refs) {
    final activities = refs.activityTypes
        .where((a) => _customer ? a.appliesToCustomer() : a.appliesToSupplier())
        .toList();
    final phoneE164 = ContactLauncher.toE164(_phone.text);
    final repId = _representativeId ?? refs.myRepresentativeId;

    return Form(
      key: _formKey,
      autovalidateMode: _showErrors
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const InfoStrip(
            icon: Icons.bolt_rounded,
            title: 'تسجيل سريع',
            subtitle: '(البيانات الأساسية فقط)',
            green: true,
          ),
          FieldLabel(
            _customer ? 'اسم العميل أو الشركة' : 'اسم المورد أو الشركة',
            icon: Icons.person_outline_rounded,
            required: true,
          ),
          TextFormField(
            key: const Key('party.name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: formDecoration(
              hint: _customer
                  ? 'مثال: شركة النور للصناعات البلاستيكية'
                  : 'مثال: شركة الصفوة لمواد البلاستيك',
            ),
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'اكتب اسم ${_customer ? 'العميل' : 'المورد'}'
                : null,
          ),
          const FieldLabel(
            'رقم الهاتف',
            icon: Icons.phone_rounded,
            required: true,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('party.phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() {}),
                  decoration: formDecoration(hint: '01xxxxxxxxx'),
                  validator: (v) => ContactLauncher.toE164(v ?? '') == null
                      ? 'رقم الهاتف غير صحيح'
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              _SquareAction(
                icon: Icons.call_rounded,
                colors: ActionPill.blue,
                tooltip: 'اتصال',
                onTap: phoneE164 == null
                    ? null
                    : () => ContactLauncher.call(phoneE164),
              ),
              const SizedBox(width: 6),
              _SquareAction(
                icon: Icons.chat_rounded,
                colors: ActionPill.green,
                tooltip: 'واتساب',
                onTap: phoneE164 == null
                    ? null
                    : () => ContactLauncher.whatsApp(phoneE164),
              ),
            ],
          ),
          FieldLabel(
            _customer ? 'نوع النشاط' : 'نوع المورد',
            icon: Icons.factory_outlined,
            required: true,
          ),
          ChoiceTiles<String>(
            keyPrefix: 'activity',
            options: [
              for (final a in activities)
                ChoiceOption(a.id, a.nameAr, activityIcon(a.code)),
            ],
            selected: _activityId,
            onChanged: (v) => setState(() => _activityId = v),
          ),
          if (_showErrors && _activityId == null)
            const _FieldError('اختر نوع النشاط'),
          const FieldLabel(
            'المندوب المسؤول',
            icon: Icons.badge_outlined,
            required: true,
          ),
          DropdownButtonFormField<String>(
            key: const Key('party.representative'),
            initialValue: repId,
            isExpanded: true,
            decoration: formDecoration(),
            items: [
              for (final r in refs.representatives)
                DropdownMenuItem(
                  value: r.id,
                  child: Text(
                    r.id == refs.myRepresentativeId
                        ? '${r.name} (المندوب الحالي)'
                        : r.name,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _representativeId = v),
            validator: (v) => v == null ? 'اختر المندوب المسؤول' : null,
          ),
          FieldLabel(
            _customer ? 'الخامات المهتم بها' : 'الخامات المتاحة',
            icon: Icons.layers_outlined,
          ),
          SpecsField(
            specs: [for (final c in _specs) c.describe(refs)],
            onRemove: (i) => setState(() => _specs.removeAt(i)),
            onAdd: () async {
              final picked = await pickSpec(context, allowOpen: _customer);
              if (picked != null && !_specs.contains(picked)) {
                setState(() => _specs.add(picked));
              }
            },
          ),
          const SizedBox(height: 14),
          InfoStrip(
            icon: Icons.edit_outlined,
            title: 'العنوان واللوكيشن',
            subtitle: '(يمكن استكمالهما لاحقًا)',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'بعد الحفظ استكمل العنوان من ملف '
                  '${_customer ? 'العميل' : 'المورد'} ← التفاصيل',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.colors,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> colors;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 48,
                child: Icon(icon, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, right: 4),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.error, fontSize: 12),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.hint),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}

/// تعرض حالة التحميل والخطأ بنفس الشكل في كل شاشات الملفات.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    data: data,
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => _LoadError(
      message: e is ApiException ? e.message : 'تعذر تحميل البيانات',
      onRetry: onRetry,
    ),
  );
}
