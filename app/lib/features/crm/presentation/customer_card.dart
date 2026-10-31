part of 'party_profile_screen.dart';

/// تبويبات بطاقة العميل كما في التصميم المعتمد، ثم الطلبات وسجل التواصل
/// (وظائف قائمة لا تُحذف).
const customerTabs = [
  'الملخص',
  'الخامات والجريد',
  'الموظفين',
  'المواقع',
  'المرفقات',
  'الطلبات',
  'التواصل',
];

/// بطاقة العميل بعد التسجيل (التصميم المعتمد): رأس بالصورة والاسم والحالة والرقم،
/// اتصال وواتساب ومشاركة، مؤشرات، ثم التبويبات. الإجراءات حسب الصلاحية فقط.
class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({
    required this.party,
    required this.tab,
    required this.onTab,
    required this.completeCard,
  });

  final PartyDetail party;
  final int tab;
  final ValueChanged<int> onTab;
  final Widget completeCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refs = ref.watch(referenceDataProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CustomerHeader(party: party),
        const SizedBox(height: 12),
        _QuickActions(party: party),
        const SizedBox(height: 12),
        _CustomerStats(party: party),
        const SizedBox(height: 12),
        _UnderlineTabs(labels: customerTabs, selected: tab, onChanged: onTab),
        const SizedBox(height: 12),
        ...switch (tab) {
          0 => [
            if (party.canComplete) completeCard,
            _CompanyData(party: party, refs: refs),
            const SizedBox(height: 12),
            _Overview(party: party, supplier: false),
            const SizedBox(height: 16),
            const FieldLabel(
              'آخر التعديلات',
              icon: Icons.manage_history_rounded,
            ),
            _History(party: party),
          ],
          1 => [
            if (party.interests.isEmpty)
              const _Empty('لا توجد خامات مسجلة لهذا العميل')
            else
              SectionCard(
                key: const Key('card.materials'),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final i in party.interests) SpecChip(i.spec)],
                ),
              ),
            if (party.canAdd)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('profile.addMaterial'),
                  onPressed: () =>
                      _addMaterial(context, ref, party, supplier: false),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة خامة'),
                ),
              ),
            if (ref.watch(canSeeSuppliersProvider))
              SupplierMatchesSection(customerId: party.id),
          ],
          2 => [ContactsSection(party: party)],
          3 => [LocationsSection(party: party)],
          4 => [
            AttachmentsSection(party: party, supplier: false),
            if (party.notes case final n? when n.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const FieldLabel('الملاحظات', icon: Icons.notes_rounded),
              SectionCard(child: Text(n)),
            ],
          ],
          5 => [_OrdersTab(party: party)],
          _ => [_ContactsTab(party: party)],
        },
      ],
    );
  }
}

class _CustomerHeader extends ConsumerWidget {
  const _CustomerHeader({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refs = ref.watch(referenceDataProvider).value;
    final activity = refs?.lookup(party.customerActivityId)?.nameAr;
    final summary = party.customerSummary;
    return Container(
      key: const Key('card.header'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3EAF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B3C78),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (party.number > 0)
                Container(
                  key: const Key('card.number'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '# ${customerCode(party.number)}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              IconButton(
                key: const Key('profile.favorite'),
                tooltip: party.isFavorite
                    ? 'إزالة من المفضلة'
                    : 'إضافة للمفضلة',
                onPressed: () async {
                  try {
                    await ref
                        .read(crmRepositoryProvider)
                        .setFavorite(party.id, !party.isFavorite);
                    refreshParty(ref, party.id);
                  } on ApiException catch (e) {
                    if (context.mounted) showErrorSnack(context, e.message);
                  }
                },
                icon: Icon(
                  party.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 30,
                  color: party.isFavorite
                      ? AppColors.reportsAccent
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  party.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (activity != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    activity,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (summary != null) _StatusPill(summary.status, false),
                    SyncPill(partyId: party.id),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 96,
              height: 96,
              child: LogoAvatar(party: party),
            ),
          ),
        ],
      ),
    );
  }
}

/// «C000125» من الرقم التسلسلي الذي يولده السيرفر.
String customerCode(int number) => 'C${number.toString().padLeft(6, '0')}';

/// أرقام التواصل المتاحة: أرقام الشركة ثم الموظفين.
List<(String, String)> partyNumbers(
  PartyDetail party,
  List<PartyContact> contacts,
) => [
  for (final p in party.phones) ('رقم الشركة', p.e164),
  for (final c in contacts)
    if (c.mobile case final m? when m.isNotEmpty)
      ([c.name, ?c.jobTitle].join(' - '), m),
];

/// يفتح الاتصال أو واتساب فقط: لا رسالة ولا اتصال تلقائي ولا طلب تسجيل نشاط بعده.
Future<void> openContact(
  BuildContext context,
  List<(String, String)> numbers, {
  required bool whatsApp,
}) async {
  if (numbers.isEmpty) return;
  var chosen = numbers.first.$2;
  if (numbers.length > 1) {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, number) in numbers)
              ListTile(
                key: Key('contact.number.$number'),
                leading: Icon(
                  whatsApp ? Icons.chat_rounded : Icons.phone_rounded,
                ),
                title: Text(label),
                subtitle: Text(
                  CrmFormat.phone(number),
                  textDirection: TextDirection.ltr,
                ),
                onTap: () => Navigator.pop(context, number),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    chosen = picked;
  }
  if (whatsApp) {
    await ContactLauncher.whatsApp(chosen);
  } else {
    await ContactLauncher.call(chosen);
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider(party.id)).value ?? const [];
    final numbers = partyNumbers(party, contacts);
    Widget box(
      String key,
      String label,
      IconData icon,
      Color color,
      VoidCallback? onTap,
    ) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: Key(key),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              height: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE3EAF5)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: onTap == null ? AppColors.hint : color),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: onTap == null ? AppColors.hint : color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        box(
          'profile.shareContact',
          'مشاركة بيانات التواصل',
          Icons.share_rounded,
          AppColors.primary,
          () => _shareContact(context, ref, party, contacts),
        ),
        box(
          'profile.whatsapp',
          'واتساب',
          Icons.chat_rounded,
          const Color(0xFF1FA34A),
          numbers.isEmpty
              ? null
              : () => openContact(context, numbers, whatsApp: true),
        ),
        box(
          'profile.call',
          'اتصال',
          Icons.call_rounded,
          AppColors.primary,
          numbers.isEmpty
              ? null
              : () => openContact(context, numbers, whatsApp: false),
        ),
      ],
    );
  }
}

/// مشاركة بيانات التواصل بمعاينة قبل الإرسال (الحقول والمواقع اختيارية).
Future<void> _shareContact(
  BuildContext context,
  WidgetRef ref,
  PartyDetail party,
  List<PartyContact> contacts,
) async {
  final refs = ref.read(referenceDataProvider).value;
  final locations = ref.read(locationsProvider(party.id)).value ?? const [];
  String? place(String? governorateId, String? region, String? address) {
    final gov = refs?.lookup(governorateId)?.nameAr;
    final parts = [
      if (address case final a? when a.trim().isNotEmpty) a.trim(),
      if (region case final r? when r.isNotEmpty) r,
      ?gov,
    ];
    return parts.isEmpty ? null : parts.join(' - ');
  }

  final text = await showDialog<String>(
    context: context,
    builder: (_) => ContactSharePreview(
      name: party.name,
      phone: party.primaryPhone == null
          ? null
          : CrmFormat.phone(party.primaryPhone!.e164),
      employees: [
        for (final c in contacts)
          (
            c.name,
            c.jobTitle,
            c.mobile == null ? null : CrmFormat.phone(c.mobile!),
          ),
      ],
      email: party.email,
      address: place(party.governorateId, party.region, party.addressLine),
      locations: [
        for (final l in locations)
          (l.title, place(l.governorateId, l.region, l.addressLine), l.link),
      ],
    ),
  );
  if (text != null) await ref.read(shareServiceProvider).text(text);
}

class _CustomerStats extends ConsumerWidget {
  const _CustomerStats({required this.party});

  final PartyDetail party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(clockProvider)();
    final created = party.recordDate ?? party.createdAt;
    final s = party.customerSummary;
    String day(DateTime? d) => d == null ? '—' : CrmFormat.isoDay(d);
    final tiles = [
      (
        'منذ التسجيل',
        created == null
            ? '—'
            : '${DateTime(today.year, today.month, today.day).difference(DateTime(created.year, created.month, created.day)).inDays} يوم',
        const Color(0xFFEFF3F8),
        AppColors.textPrimary,
      ),
      (
        'آخر تواصل',
        day(s?.lastContactAt),
        const Color(0xFFFFF4E0),
        const Color(0xFFB26A00),
      ),
      (
        'آخر طلب',
        day(s?.lastDealDate),
        const Color(0xFFE6F6E8),
        AppColors.greenDark,
      ),
      (
        'المتابعة القادمة',
        day(s?.nextFollowUpAt),
        const Color(0xFFE6F0FC),
        AppColors.primary,
      ),
    ];
    return Row(
      children: [
        for (final (i, (label, value, bg, fg)) in tiles.indexed)
          Expanded(
            child: Container(
              key: Key('card.stat.$i'),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, label) in labels.indexed)
          InkWell(
            key: Key('tab.$i'),
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: i == selected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500,
                  color: i == selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// «بيانات الشركة» في الملخص: الضغط على الهاتف يتصل، وعلى البريد يفتح البريد،
/// والموقع يفتح الخريطة.
class _CompanyData extends ConsumerWidget {
  const _CompanyData({required this.party, required this.refs});

  final PartyDetail party;
  final ReferenceData? refs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(locationsProvider(party.id)).value ?? const [];
    final main =
        locations.where((l) => l.isDefault).firstOrNull ??
        locations.firstOrNull;
    final address = [
      party.addressLine,
      party.region,
      refs?.lookup(party.governorateId)?.nameAr,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' - ');
    final rows = <(IconData, String, String?, VoidCallback?, Key?)>[
      (Icons.apartment_rounded, 'اسم الشركة', party.name, null, null),
      (
        Icons.work_outline_rounded,
        'النشاط',
        refs?.lookup(party.customerActivityId)?.nameAr,
        null,
        null,
      ),
      for (final (i, p) in party.phones.indexed)
        (
          Icons.phone_rounded,
          'رقم الهاتف',
          CrmFormat.phone(p.e164),
          () => ContactLauncher.call(p.e164),
          Key('details.phone.$i'),
        ),
      (
        Icons.email_outlined,
        'البريد الإلكتروني',
        party.email,
        party.email == null ? null : () => ContactLauncher.email(party.email!),
        const Key('details.email'),
      ),
      (
        Icons.location_on_outlined,
        'العنوان الرئيسي',
        address.isEmpty ? null : address,
        null,
        null,
      ),
      if (main?.link case final link?)
        (
          Icons.map_outlined,
          'الموقع على الخريطة',
          'عرض على خرائط جوجل',
          () => ContactLauncher.openUrl(link),
          const Key('details.map'),
        ),
      (Icons.person_rounded, 'المندوب', party.representativeName, null, null),
    ];
    return SectionCard(
      key: const Key('card.company'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'بيانات الشركة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 6),
          for (final (icon, label, value, onTap, key) in rows)
            InkWell(
              key: key,
              onTap: value == null ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 104,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value == null || value.isEmpty ? '—' : value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: onTap != null && value != null
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// شريط الإجراءات أسفل البطاقة: التعديل والحذف للمدير العام فقط، والإضافة لمن له
/// صلاحية الإضافة، والمزيد (إسناد، طلب، تواصل).
class _CustomerActions extends ConsumerWidget {
  const _CustomerActions({required this.party, required this.onTab});

  final PartyDetail party;
  final ValueChanged<int> onTab;

  Future<void> _more(BuildContext context, WidgetRef ref) async {
    final refs = ref.read(referenceDataProvider).value;
    final canAssign = ref.read(canTeamAssignProvider) && refs != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (party.canAdd) ...[
              ListTile(
                key: const Key('more.order'),
                leading: const Icon(Icons.add_shopping_cart_rounded),
                title: const Text('تسجيل طلب جديد'),
                onTap: () => Navigator.pop(context, 'order'),
              ),
              ListTile(
                key: const Key('more.contact'),
                leading: const Icon(Icons.chat_bubble_rounded),
                title: const Text('تسجيل تواصل جديد'),
                onTap: () => Navigator.pop(context, 'contact'),
              ),
            ],
            if (canAssign)
              ListTile(
                key: const Key('profile.assign'),
                leading: const Icon(Icons.assignment_ind_outlined),
                title: const Text('إسناد لمندوب'),
                onTap: () => Navigator.pop(context, 'assign'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'order':
        await context.push(CrmRoutes.newOrder(party.id));
      case 'contact':
        await context.push(CrmRoutes.newContact(party.id));
      case 'assign':
        await _assign(context, ref, party, refs!);
    }
  }

  /// للأدوار التي لا تعدّل: إضافة بيانات جديدة فقط (لا تغيير لقيمة محفوظة).
  Future<void> _add(BuildContext context) async {
    final tab = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, label, icon) in [
              (1, 'إضافة خامة أو Grade', Icons.layers_rounded),
              (2, 'إضافة موظف', Icons.group_add_rounded),
              (3, 'إضافة موقع', Icons.add_location_alt_rounded),
              (4, 'إضافة مرفق', Icons.attach_file_rounded),
            ])
              ListTile(
                key: Key('profile.addTo.$i'),
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (tab != null) onTab(tab);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMore = party.canAdd || ref.watch(canTeamAssignProvider);
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            if (party.canEdit)
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('profile.edit'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () =>
                      context.push(CrmRoutes.editDetails(party.id)),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('تعديل'),
                ),
              )
            else if (party.canAdd)
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('profile.addMore'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('استكمال'),
                ),
              ),
            if (party.canEdit) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('profile.delete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFDE4E4),
                    foregroundColor: AppColors.error,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () => _deleteParty(context, ref, party),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('حذف'),
                ),
              ),
            ],
            if (hasMore) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('profile.more'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(56, 50),
                ),
                onPressed: () => _more(context, ref),
                child: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
