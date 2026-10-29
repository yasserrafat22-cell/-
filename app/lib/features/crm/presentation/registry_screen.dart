import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/crm_providers.dart';
import '../data/crm_repository.dart';
import '../domain/crm_format.dart';
import '../domain/crm_models.dart';
import 'contact_launcher.dart';
import 'crm_routes.dart';
import 'crm_widgets.dart';

/// «السجل»: كل العملاء والموردين، بحث سريع وفلاتر بالخامة والشركة والـ Grade
/// وبلد الصنع والحالة، والمفضلة. الضغط على أي بطاقة يفتح الملف الأصلي.
class RegistryScreen extends ConsumerStatefulWidget {
  const RegistryScreen({super.key});

  @override
  ConsumerState<RegistryScreen> createState() => _RegistryScreenState();
}

class _RegistryScreenState extends ConsumerState<RegistryScreen> {
  /// التبويبات حسب الصلاحية: الموردون لمن يطّلع على الكل فقط، والمحذوفات للمدير.
  List<(String, String?, bool, bool)> get _tabs => [
    ('العملاء', 'customer', false, false),
    if (ref.read(canSeeSuppliersProvider))
      ('الموردين', 'supplier', false, false),
    ('المفضلة', null, true, false),
    if (ref.read(canManageProvider)) ('المحذوفات', null, false, true),
  ];

  final _search = TextEditingController();
  Timer? _debounce;
  int _tab = 0;
  RegistryFilter _filter = const RegistryFilter(role: 'customer');

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(RegistryFilter filter) => setState(() => _filter = filter);

  void _setTab(int tab) {
    _tab = tab;
    final (_, role, favorites, deleted) = _tabs[tab];
    _setFilter(
      RegistryFilter(
        role: role,
        favorites: favorites,
        deleted: deleted,
        query: _filter.query,
        materialId: _filter.materialId,
        manufacturerId: _filter.manufacturerId,
        gradeId: _filter.gradeId,
        countryId: _filter.countryId,
        status: _filter.status,
      ),
    );
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _setFilter(_filter.copyWith(query: text)),
    );
  }

  Future<T?> _pick<T>(String title, List<(T, String)> options) =>
      showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (value, label) in options)
                      ListTile(
                        key: Key('registry.option.$label'),
                        title: Text(label),
                        onTap: () => Navigator.of(context).pop(value),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _open(RegistryItem item) async {
    if (_filter.deleted) return _restore(item);
    await context.push(
      CrmRoutes.party(
        item.id,
        supplier: _filter.role == 'supplier' || (!item.isCustomer),
      ),
    );
    ref.invalidate(registryProvider);
  }

  Future<void> _restore(RegistryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة السجل؟'),
        content: Text(item.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('registry.confirmRestore'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(crmRepositoryProvider).restoreParty(item.id);
      ref.invalidate(registryProvider);
      if (mounted) showSuccessSnack(context, 'تمت الاستعادة');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  Future<void> _toggleFavorite(RegistryItem item) async {
    try {
      await ref
          .read(crmRepositoryProvider)
          .setFavorite(item.id, !item.isFavorite);
      ref
        ..invalidate(registryProvider)
        ..invalidate(partyProvider(item.id));
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refs = ref.watch(referenceDataProvider).value;
    final results = ref.watch(registryProvider(_filter));
    final role = _filter.role;
    return CrmScaffold(
      title: 'السجل',
      icon: Icons.folder_shared_rounded,
      bottom: role == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ActionPill(
                key: const Key('registry.add'),
                label: role == 'customer'
                    ? 'إضافة عميل جديد'
                    : 'إضافة مورد جديد',
                icon: Icons.person_add_alt_1_rounded,
                colors: ActionPill.blue,
                onTap: () async {
                  await context.push(
                    role == 'customer'
                        ? CrmRoutes.newCustomer
                        : CrmRoutes.newSupplier,
                  );
                  ref.invalidate(registryProvider);
                },
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(registryProvider);
          await ref.read(registryProvider(_filter).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            SegmentTabs(
              labels: [for (final t in _tabs) t.$1],
              selected: _tab,
              onChanged: _setTab,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('registry.search'),
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: formDecoration(
                hint: 'الاسم، الهاتف، الخامة، الشركة، Grade، البلد',
                prefix: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            if (refs != null) _filters(refs),
            const SizedBox(height: 4),
            ...switch (results) {
              AsyncData(:final value) => _results(value, refs),
              AsyncError(:final error) => [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        error is ApiException
                            ? error.message
                            : 'تعذر تحميل السجل',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(registryProvider),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ],
              _ => [
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            },
          ],
        ),
      ),
    );
  }

  Widget _filters(ReferenceData refs) {
    final material = _filter.materialId == null
        ? null
        : refs.material(_filter.materialId!);
    final grade = _filter.gradeId == null ? null : refs.grade(_filter.gradeId!);
    final maker = _filter.manufacturerId == null
        ? null
        : refs.manufacturer(_filter.manufacturerId!);
    final country = _filter.countryId == null
        ? null
        : refs.country(_filter.countryId!);
    final supplierView = _filter.role == 'supplier';
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FilterChip(
          key: const Key('registry.material'),
          label: material?.code ?? 'الخامة',
          active: material != null,
          onTap: () async {
            final id = await _pick('نوع الخامة', [
              for (final m in refs.materials) (m.id, m.code),
            ]);
            if (id != null) {
              _setFilter(
                _filter.copyWith(materialId: () => id, gradeId: () => null),
              );
            }
          },
          onClear: () => _setFilter(
            _filter.copyWith(materialId: () => null, gradeId: () => null),
          ),
        ),
        _FilterChip(
          key: const Key('registry.maker'),
          label: maker?.name ?? 'الشركة',
          active: maker != null,
          onTap: () async {
            final id = await _pick('الشركة المصنّعة', [
              for (final m in refs.manufacturers) (m.id, m.name),
            ]);
            if (id != null) {
              _setFilter(_filter.copyWith(manufacturerId: () => id));
            }
          },
          onClear: () =>
              _setFilter(_filter.copyWith(manufacturerId: () => null)),
        ),
        if (material != null)
          _FilterChip(
            key: const Key('registry.grade'),
            label: grade?.code ?? 'Grade',
            active: grade != null,
            onTap: () async {
              final id = await _pick('Grade', [
                for (final g in material.grades)
                  (
                    g.id,
                    '${g.code} — ${g.manufacturerId == null ? 'الشركة غير محددة' : refs.manufacturer(g.manufacturerId!)?.name ?? ''}',
                  ),
              ]);
              if (id != null) _setFilter(_filter.copyWith(gradeId: () => id));
            },
            onClear: () => _setFilter(_filter.copyWith(gradeId: () => null)),
          ),
        _FilterChip(
          key: const Key('registry.country'),
          label: country?.nameAr ?? 'بلد الصنع',
          active: country != null,
          onTap: () async {
            final id = await _pick('بلد الصنع', [
              for (final c in refs.countries) (c.id, c.nameAr),
            ]);
            if (id != null) _setFilter(_filter.copyWith(countryId: () => id));
          },
          onClear: () => _setFilter(_filter.copyWith(countryId: () => null)),
        ),
        _FilterChip(
          key: const Key('registry.status'),
          label: _filter.status == null
              ? 'الحالة'
              : CrmFormat.status(_filter.status!, supplier: supplierView),
          active: _filter.status != null,
          onTap: () async {
            final status = await _pick('الحالة', [
              for (final s in PartyStatus.values)
                (s, CrmFormat.status(s, supplier: supplierView)),
            ]);
            if (status != null) {
              _setFilter(_filter.copyWith(status: () => status));
            }
          },
          onClear: () => _setFilter(_filter.copyWith(status: () => null)),
        ),
      ],
    );
  }

  List<Widget> _results(RegistryPage page, ReferenceData? refs) {
    if (page.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _filter.favorites
                ? 'لا توجد عناصر في المفضلة بعد. اضغط النجمة في أي ملف لإضافته.'
                : 'لا توجد نتائج مطابقة',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '${page.total} نتيجة',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
          ),
        ),
      ),
      for (final item in page.items)
        _RegistryCard(
          item: item,
          refs: refs,
          supplierView:
              _filter.role == 'supplier' ||
              (_filter.role == null && !item.isCustomer),
          onOpen: () => _open(item),
          onFavorite: () => _toggleFavorite(item),
        ),
      if (page.total > page.items.length)
        _MoreResults(
          filter: _filter,
          skip: page.items.length,
          refs: refs,
          onOpen: _open,
          onFavorite: _toggleFavorite,
        ),
    ];
  }
}

/// الصفحات التالية تُحمّل عند الطلب فقط.
class _MoreResults extends ConsumerStatefulWidget {
  const _MoreResults({
    required this.filter,
    required this.skip,
    required this.refs,
    required this.onOpen,
    required this.onFavorite,
  });

  final RegistryFilter filter;
  final int skip;
  final ReferenceData? refs;
  final ValueChanged<RegistryItem> onOpen;
  final ValueChanged<RegistryItem> onFavorite;

  @override
  ConsumerState<_MoreResults> createState() => _MoreResultsState();
}

class _MoreResultsState extends ConsumerState<_MoreResults> {
  RegistryPage? _page;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(crmRepositoryProvider)
          .registry(widget.filter, skip: widget.skip);
      if (mounted) setState(() => _page = page);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return TextButton(
        key: const Key('registry.more'),
        onPressed: _loading ? null : _load,
        child: Text(_loading ? 'جارٍ التحميل…' : 'عرض المزيد'),
      );
    }
    return Column(
      children: [
        for (final item in page.items)
          _RegistryCard(
            item: item,
            refs: widget.refs,
            supplierView:
                widget.filter.role == 'supplier' ||
                (widget.filter.role == null && !item.isCustomer),
            onOpen: () => widget.onOpen(item),
            onFavorite: () => widget.onFavorite(item),
          ),
        if (page.total > widget.skip + page.items.length)
          _MoreResults(
            filter: widget.filter,
            skip: widget.skip + page.items.length,
            refs: widget.refs,
            onOpen: widget.onOpen,
            onFavorite: widget.onFavorite,
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? AppColors.primary : Colors.white,
    shape: StadiumBorder(
      side: BorderSide(
        color: active ? AppColors.primary : AppColors.fieldBorder,
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: active ? onClear : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: active ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              active ? Icons.close_rounded : Icons.expand_more_rounded,
              size: 16,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _RegistryCard extends StatelessWidget {
  const _RegistryCard({
    required this.item,
    required this.refs,
    required this.supplierView,
    required this.onOpen,
    required this.onFavorite,
  });

  final RegistryItem item;
  final ReferenceData? refs;
  final bool supplierView;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  String get _last {
    final s = item.summary;
    if (s?.lastDealDate case final d?) {
      return '${supplierView ? 'آخر توريد' : 'آخر طلب'}: ${CrmFormat.date(d)}';
    }
    if (s?.lastContactAt case final c?) {
      return 'آخر تواصل: ${CrmFormat.date(c.toLocal())}';
    }
    return supplierView ? 'لم يتم التوريد بعد' : 'لم يتم الطلب بعد';
  }

  @override
  Widget build(BuildContext context) {
    final activity = refs?.lookup(item.activityId)?.nameAr;
    final place = [
      refs?.lookup(item.governorateId)?.nameAr,
      item.region,
    ].nonNulls.where((s) => s.isNotEmpty).join(' - ');
    final status = item.summary?.status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
        child: InkWell(
          key: Key('registry.item.${item.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.fieldFill,
                  child: Icon(
                    supplierView
                        ? Icons.local_shipping_rounded
                        : Icons.factory_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                              ),
                            ),
                          ),
                          IconButton(
                            key: Key('registry.favorite.${item.id}'),
                            tooltip: item.isFavorite
                                ? 'إزالة من المفضلة'
                                : 'إضافة للمفضلة',
                            visualDensity: VisualDensity.compact,
                            onPressed: onFavorite,
                            icon: Icon(
                              item.isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: item.isFavorite
                                  ? AppColors.reportsAccent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (activity != null || place.isNotEmpty)
                        Text(
                          [?activity, if (place.isNotEmpty) place].join(' • '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      if (item.specs.isNotEmpty || item.match == 'open') ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (item.match == 'open')
                              const Pill(
                                'مطابقة مفتوحة: يقبل أي شركة',
                                color: SpecChip.openColor,
                                textColor: SpecChip.openText,
                              ),
                            for (final spec in item.specs.take(3))
                              SpecChip(spec),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (status != null) ...[
                            Pill.forStatusColor(
                              CrmFormat.status(status, supplier: supplierView),
                              status == PartyStatus.active ||
                                  status == PartyStatus.newParty,
                              status == PartyStatus.needsFollowUp,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              _last,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (item.primaryPhone case final phone?) ...[
                            IconButton(
                              tooltip: 'اتصال',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ContactLauncher.call(phone),
                              icon: const Icon(
                                Icons.phone_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'واتساب',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ContactLauncher.whatsApp(phone),
                              icon: const Icon(
                                Icons.chat_rounded,
                                color: AppColors.green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
