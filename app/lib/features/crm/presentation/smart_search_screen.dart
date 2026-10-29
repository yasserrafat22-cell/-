import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/document_services.dart';
import '../../../core/device/file_services.dart';
import '../../../core/device/share_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'contact_launcher.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';

/// الحقول المسموح بمشاركتها من البطاقة.
enum ShareFields { name, namePhone, nameSpecs, all }

String cardText(SearchCard c, ShareFields fields) {
  final kind = c.isSupplier && !c.isCustomer
      ? 'مورد'
      : c.isCustomer && !c.isSupplier
      ? 'عميل'
      : 'عميل ومورد';
  final specs = c.specs.map((s) => s.label).join('، ');
  return [
    '${c.name} ($kind)',
    if (fields case ShareFields.namePhone || ShareFields.all)
      if (c.phone case final p?)
        'هاتف: ${CrmFormat.phone(p)}${c.contactName == null ? '' : ' — ${c.contactName}'}',
    if (fields case ShareFields.nameSpecs || ShareFields.all)
      if (specs.isNotEmpty) 'الخامات: $specs',
    if (fields == ShareFields.all)
      if (c.email case final e? when e.isNotEmpty) 'بريد: $e',
  ].join('\n');
}

/// البحث الذكي اللحظي: النتائج أثناء الكتابة، الموردون أولًا ثم العملاء (تحت بعض).
class SmartSearchScreen extends ConsumerStatefulWidget {
  const SmartSearchScreen({super.key});

  @override
  ConsumerState<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends ConsumerState<SmartSearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  SearchQuery _query = const SearchQuery();
  bool _selecting = false;
  final _selected = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => setState(() {
        _query = SearchQuery(text: value);
        _selected.clear();
      }),
    );
  }

  void _pick(SearchSuggestion s) => setState(() {
    _query = SearchQuery(
      text: '',
      materialId: s.kind == 'material' ? s.id : s.materialId,
      manufacturerId: s.kind == 'manufacturer' ? s.id : s.manufacturerId,
      gradeId: s.kind == 'grade' ? s.id : null,
      label: s.label,
    );
    _selected.clear();
  });

  /// كل مشاركة أو طباعة أو تصدير تُعتمد من السيرفر أولًا (وتُسجَّل)؛ المرفوض لا يُنفذ.
  Future<bool> _authorize(String scope, int count) async {
    try {
      await ref
          .read(crmRepositoryProvider)
          .authorizeShare(scope, count, query: _query.title);
      return true;
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
      return false;
    }
  }

  Future<void> _shareCard(SearchCard card) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _CardShareDialog(card: card),
    );
    if (text == null || !await _authorize('card', 1)) return;
    await ref.read(shareServiceProvider).text(text);
  }

  List<SearchCard> _chosen(SearchResults r) => [
    for (final c in [...r.suppliers, ...r.customers])
      if (!_selecting || _selected.contains(c.partyId)) c,
  ];

  TableDocument _document(SearchResults r) {
    List<String> row(SearchCard c) => [
      c.name,
      c.contactName ?? '',
      c.phone == null ? '' : CrmFormat.phone(c.phone!),
      c.specs.map((s) => s.label).join('، '),
      c.exact ? 'مطابقة دقيقة' : 'بديل محتمل',
      c.reasons.join('، '),
    ];
    bool keep(SearchCard c) => !_selecting || _selected.contains(c.partyId);
    return TableDocument(
      title: 'نتائج البحث: ${_query.title}',
      subtitle: CrmFormat.dateTime(ref.read(clockProvider)()),
      headers: const [
        'الاسم',
        'جهة الاتصال',
        'الهاتف',
        'الخامات',
        'المطابقة',
        'السبب',
      ],
      rows: const [],
      sections: [
        ('الموردون', [for (final c in r.suppliers.where(keep)) row(c)]),
        (
          'العملاء المناسبون',
          [for (final c in r.customers.where(keep)) row(c)],
        ),
      ],
    );
  }

  Future<void> _shareList(SearchResults r) async {
    final cards = _chosen(r);
    if (cards.isEmpty) return;
    if (cards.length <= 20) {
      if (!await _authorize(_selecting ? 'selection' : 'list', cards.length)) {
        return;
      }
      final suppliers = cards.where((c) => r.suppliers.contains(c)).toList();
      final customers = cards.where((c) => r.customers.contains(c)).toList();
      await ref
          .read(shareServiceProvider)
          .text(
            [
              'نتائج البحث: ${_query.title}',
              if (suppliers.isNotEmpty) ...[
                '\n— الموردون —',
                for (final c in suppliers) cardText(c, ShareFields.all),
              ],
              if (customers.isNotEmpty) ...[
                '\n— العملاء المناسبون —',
                for (final c in customers) cardText(c, ShareFields.all),
              ],
            ].join('\n'),
          );
      return;
    }
    // القوائم الكبيرة ملفًا بدل رسالة طويلة.
    await _pdf(r, share: true);
  }

  Future<void> _pdf(SearchResults r, {required bool share}) async {
    final count = _chosen(r).length;
    if (count == 0 || !await _authorize('pdf', count)) return;
    final bytes = await ref.read(documentServicesProvider).pdf(_document(r));
    await _shareBytes(bytes, 'search.pdf', 'application/pdf');
  }

  Future<void> _print(SearchResults r) async {
    final count = _chosen(r).length;
    if (count == 0 || !await _authorize('print', count)) return;
    await ref.read(documentServicesProvider).print(_document(r), 'نتائج البحث');
  }

  Future<void> _excel(SearchResults r) async {
    final ids = _selecting ? _selected.toList() : null;
    try {
      final bytes = await ref
          .read(crmRepositoryProvider)
          .exportSearch(_query, ids: ids);
      await _shareBytes(
        bytes,
        'search.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  Future<void> _shareBytes(Uint8List bytes, String name, String mime) async {
    final path = await ref
        .read(fileServicesProvider)
        .writeTemp('search', name, bytes);
    await ref.read(shareServiceProvider).file(path, mimeType: mime);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_query));
    final bulk = ref.watch(canShareBulkProvider);
    final value = results.value;
    return CrmScaffold(
      title: 'البحث',
      icon: Icons.search_rounded,
      actions: [
        IconButton(
          key: const Key('search.registry'),
          tooltip: 'السجل والمفضلة',
          onPressed: () => context.push(CrmRoutes.registry),
          icon: const Icon(Icons.folder_shared_rounded, color: Colors.white),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            key: const Key('search.field'),
            controller: _text,
            autofocus: true,
            onChanged: _onChanged,
            decoration: formDecoration(
              hint: 'اسم، هاتف، موظف، خامة، شركة مصنّعة، Grade',
              prefix: const Icon(Icons.search_rounded),
            ),
          ),
          if (_query.label case final label?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  key: const Key('search.picked'),
                  label: Text(label),
                  onDeleted: () =>
                      setState(() => _query = SearchQuery(text: _text.text)),
                ),
              ),
            ),
          if (value != null &&
              value.suggestions.isNotEmpty &&
              _query.label == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in value.suggestions)
                    ActionChip(
                      key: Key('search.suggest.${s.kind}.${s.id}'),
                      avatar: Icon(switch (s.kind) {
                        'manufacturer' => Icons.factory_outlined,
                        'material' => Icons.category_outlined,
                        _ => Icons.label_outline,
                      }, size: 16),
                      label: Text(s.label),
                      onPressed: () => _pick(s),
                    ),
                ],
              ),
            ),
          if (bulk && value != null && value.total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    key: const Key('search.select'),
                    onPressed: () => setState(() {
                      _selecting = !_selecting;
                      _selected.clear();
                    }),
                    icon: Icon(
                      _selecting
                          ? Icons.close_rounded
                          : Icons.checklist_rounded,
                    ),
                    label: Text(_selecting ? 'إلغاء التحديد' : 'تحديد نتائج'),
                  ),
                  TextButton.icon(
                    key: const Key('search.share'),
                    onPressed: () => _shareList(value),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('مشاركة'),
                  ),
                  TextButton.icon(
                    key: const Key('search.print'),
                    onPressed: () => _print(value),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('طباعة'),
                  ),
                  TextButton.icon(
                    key: const Key('search.pdf'),
                    onPressed: () => _pdf(value, share: true),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('PDF'),
                  ),
                  TextButton.icon(
                    key: const Key('search.excel'),
                    onPressed: () => _excel(value),
                    icon: const Icon(Icons.table_view_rounded),
                    label: const Text('Excel'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          ...switch (results) {
            AsyncData() when _query.isEmpty => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'اكتب حرفين على الأقل؛ تظهر النتائج أثناء الكتابة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
            AsyncData(:final value) when value.total == 0 => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد نتائج مطابقة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
            AsyncData(:final value) => [
              if (value.suppliers.isNotEmpty) ...[
                FieldLabel(
                  'الموردون (${value.suppliers.length})',
                  icon: Icons.local_shipping_outlined,
                ),
                for (final c in value.suppliers) _card(c),
              ],
              if (value.customers.isNotEmpty) ...[
                FieldLabel(
                  'العملاء المناسبون (${value.customers.length})',
                  icon: Icons.groups_rounded,
                ),
                for (final c in value.customers) _card(c),
              ],
            ],
            AsyncError(:final error) => [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error is ApiException ? error.message : '$error',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            _ => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          },
        ],
      ),
    );
  }

  Widget _card(SearchCard c) {
    final supplier = c.isSupplier && !c.isCustomer;
    return Padding(
      key: Key('search.card.${c.partyId}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: c.exact ? AppColors.primary : AppColors.fieldBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _selecting
              ? () => setState(() {
                  _selected.contains(c.partyId)
                      ? _selected.remove(c.partyId)
                      : _selected.add(c.partyId);
                })
              : () => context.push(
                  CrmRoutes.party(c.partyId, supplier: supplier),
                ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_selecting)
                      Checkbox(
                        key: Key('search.check.${c.partyId}'),
                        value: _selected.contains(c.partyId),
                        onChanged: (_) => setState(() {
                          _selected.contains(c.partyId)
                              ? _selected.remove(c.partyId)
                              : _selected.add(c.partyId);
                        }),
                      ),
                    Expanded(
                      child: Text(
                        c.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    if (c.isCustomer)
                      const Pill(
                        'عميل',
                        color: Color(0xFFDFF3D3),
                        textColor: AppColors.greenDark,
                      ),
                    if (c.isSupplier) ...[
                      const SizedBox(width: 4),
                      const Pill(
                        'مورد',
                        color: Color(0xFFDCEBFA),
                        textColor: AppColors.primary,
                      ),
                    ],
                  ],
                ),
                if (c.specs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [for (final s in c.specs) SpecChip(s)],
                    ),
                  ),
                for (final r in c.reasons)
                  Text(
                    '• $r',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (!c.exact)
                  const Text(
                    'بديل محتمل — راجع المواصفات قبل العرض',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9A6200)),
                  ),
                Row(
                  children: [
                    if (c.phone case final phone?) ...[
                      Expanded(
                        child: Text(
                          [CrmFormat.phone(phone), ?c.contactName].join(' — '),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      IconButton(
                        key: Key('search.call.${c.partyId}'),
                        tooltip: 'اتصال',
                        onPressed: () => ContactLauncher.call(phone),
                        icon: const Icon(
                          Icons.call_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      IconButton(
                        key: Key('search.whatsapp.${c.partyId}'),
                        tooltip: 'واتساب',
                        onPressed: () => ContactLauncher.whatsApp(phone),
                        icon: const Icon(
                          Icons.chat_rounded,
                          color: AppColors.greenDark,
                        ),
                      ),
                    ] else
                      const Spacer(),
                    if (c.email case final email? when email.isNotEmpty)
                      IconButton(
                        key: Key('search.email.${c.partyId}'),
                        tooltip: 'بريد',
                        onPressed: () => ContactLauncher.email(email),
                        icon: const Icon(
                          Icons.email_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    IconButton(
                      key: Key('search.shareCard.${c.partyId}'),
                      tooltip: 'مشاركة البطاقة',
                      onPressed: () => _shareCard(c),
                      icon: const Icon(Icons.share_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// معاينة مشاركة بطاقة واحدة مع اختيار الحقول؛ لا يُرسل شيء دون ضغط المستخدم.
class _CardShareDialog extends StatefulWidget {
  const _CardShareDialog({required this.card});

  final SearchCard card;

  @override
  State<_CardShareDialog> createState() => _CardShareDialogState();
}

class _CardShareDialogState extends State<_CardShareDialog> {
  var _fields = ShareFields.namePhone;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('مشاركة البطاقة'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<ShareFields>(
          groupValue: _fields,
          onChanged: (v) => setState(() => _fields = v!),
          child: Column(
            children: [
              for (final (f, label) in const [
                (ShareFields.name, 'الاسم فقط'),
                (ShareFields.namePhone, 'الاسم ورقم الهاتف'),
                (ShareFields.nameSpecs, 'الاسم والخامة والـ Grade'),
                (ShareFields.all, 'كل البيانات المسموح بها'),
              ])
                RadioListTile<ShareFields>(
                  key: Key('share.fields.${f.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: f,
                  title: Text(label),
                ),
            ],
          ),
        ),
        const Divider(),
        Text(
          cardText(widget.card, _fields),
          key: const Key('share.preview'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton.icon(
        key: const Key('share.send'),
        onPressed: () => Navigator.pop(context, cardText(widget.card, _fields)),
        icon: const Icon(Icons.share_rounded),
        label: const Text('مشاركة'),
      ),
    ],
  );
}
