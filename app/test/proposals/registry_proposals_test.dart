@Tags(['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qadisiyah/core/theme/app_colors.dart';
import 'package:qadisiyah/features/crm/presentation/crm_widgets.dart';

import '../golden/screens_golden_test.dart' show withShadows;
import '../helpers/test_app.dart';

/// مقترحات شاشات السجل واختيار الخامة والمواقع والمرفقات والكتالوج.
/// داخل test فقط ببيانات تجريبية، ولا تدخل التطبيق قبل الموافقة.

const _muted = TextStyle(color: AppColors.textSecondary, fontSize: 12.5);
const _bold = TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5);

Widget _chip(String text, {bool selected = false, IconData? icon}) => Padding(
  padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.fieldBorder,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
        if (icon != null) ...[
          const SizedBox(width: 4),
          Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ],
      ],
    ),
  ),
);

/// شريحة خامة دقيقة: النوع · الشركة · Grade · البلد، كل جزء منفصل حتى لا
/// يختلط ترتيب العربي واللاتيني.
Widget _spec(String text, {Color? color, bool pending = false}) => Container(
  margin: const EdgeInsetsDirectional.only(end: 6, top: 4),
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color ?? AppColors.fieldFill,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    textDirection: TextDirection.ltr,
    children: [
      for (final (i, part) in text.split(' · ').indexed) ...[
        if (i > 0)
          const Text(
            '  ·  ',
            style: TextStyle(fontSize: 12, color: AppColors.hint),
          ),
        Text(
          part,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
      if (pending) ...[
        const SizedBox(width: 4),
        const Icon(
          Icons.hourglass_top_rounded,
          size: 14,
          color: Color(0xFF9A6200),
        ),
      ],
    ],
  ),
);

Widget _search(String hint) => TextField(
  decoration: formDecoration(
    hint: hint,
    prefix: const Icon(Icons.search_rounded),
  ),
);

Widget _section(String title, IconData icon, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 8),
  child: Row(
    children: [
      Icon(icon, color: AppColors.primary, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      ?trailing,
    ],
  ),
);

Widget _smallAction(String label, IconData icon, {Color? color}) => Padding(
  padding: const EdgeInsetsDirectional.only(end: 6),
  child: OutlinedButton.icon(
    onPressed: () {},
    style: OutlinedButton.styleFrom(
      foregroundColor: color ?? AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      side: const BorderSide(color: AppColors.fieldBorder),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontSize: 12.5)),
  ),
);

Widget _addPill(String label, IconData icon) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
  child: ActionPill(
    label: label,
    icon: icon,
    colors: ActionPill.blue,
    onTap: () {},
  ),
);

// ---------------------------------------------------------------- السجل

class RegistryProposal extends StatelessWidget {
  const RegistryProposal({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(
      String name,
      String sub,
      List<String> specs,
      String status,
      int kind,
      String last, {
      bool fav = false,
      bool open = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.fieldFill,
              child: Icon(Icons.factory_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: _bold)),
                      Icon(
                        fav ? Icons.star_rounded : Icons.star_border_rounded,
                        color: fav
                            ? AppColors.reportsAccent
                            : AppColors.textSecondary,
                      ),
                    ],
                  ),
                  Text(sub, style: _muted),
                  Wrap(
                    children: [
                      for (final s in specs)
                        _spec(s, color: open ? const Color(0xFFFFF1D6) : null),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Pill.forStatusColor(status, kind == 0, kind == 1),
                      const SizedBox(width: 8),
                      Expanded(child: Text(last, style: _muted)),
                      const Icon(
                        Icons.phone_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.chat_rounded,
                        color: AppColors.green,
                        size: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return CrmScaffold(
      title: 'السجل',
      icon: Icons.folder_shared_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SegmentTabs(
            labels: const ['العملاء', 'الموردين', 'المفضلة'],
            selected: 1,
            onChanged: (_) {},
          ),
          const SizedBox(height: 12),
          _search('الاسم، الهاتف، الخامة، الشركة، Grade، البلد'),
          const SizedBox(height: 10),
          Wrap(
            children: [
              _chip('PP', selected: true, icon: Icons.close_rounded),
              _chip('الشركة', icon: Icons.expand_more_rounded),
              _chip('Grade', icon: Icons.expand_more_rounded),
              _chip('بلد الصنع', icon: Icons.expand_more_rounded),
              _chip('الحالة', icon: Icons.expand_more_rounded),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('3 موردين يوفّرون PP', style: _muted),
          ),
          card(
            'مورد تجريبي أ للبتروكيماويات',
            'مستورد • الإسكندرية',
            ['PP · SABIC · PP500 · السعودية', 'PP · المتقدمة · 129H'],
            'نشط',
            0,
            'آخر توريد: 15 أكتوبر',
            fav: true,
          ),
          card(
            'مورد تجريبي ب',
            'تاجر • القاهرة',
            ['PP · Chevron Phillips · MARLEX 030 ⏳'],
            'يحتاج متابعة',
            1,
            'آخر تواصل: 2 أغسطس',
          ),
          card(
            'مورد تجريبي ج',
            'موزع • الجيزة',
            ['PP · أي شركة'],
            'جديد',
            0,
            'لم يتم التوريد بعد',
            open: true,
          ),
        ],
      ),
      bottom: _addPill('إضافة مورد جديد', Icons.person_add_alt_1_rounded),
    );
  }
}

// ---------------------------------------------------------- اختيار الخامة

class MaterialPickerProposal extends StatelessWidget {
  const MaterialPickerProposal({super.key});

  @override
  Widget build(BuildContext context) {
    Widget option(
      String grade,
      String maker, {
      String? origins,
      bool selected = false,
      bool pending = false,
      bool unknownMaker = false,
    }) => Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE5F0FC) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.fieldBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Text(
            grade,
            textDirection: TextDirection.ltr,
            style: _bold.copyWith(fontSize: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              maker,
              style: TextStyle(
                color: unknownMaker ? AppColors.hint : AppColors.textSecondary,
                fontStyle: unknownMaker ? FontStyle.italic : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pending) const Pill('بانتظار التحقق'),
          if (origins != null) Text(origins, style: _muted),
        ],
      ),
    );

    return CrmScaffold(
      title: 'اختيار الخامة',
      icon: Icons.layers_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const FieldLabel('1. نوع الخامة', icon: Icons.category_rounded),
          Wrap(
            children: [
              for (final (i, m) in [
                'PP',
                'HDPE',
                'LDPE',
                'LLDPE',
                'PVC',
                'PS',
              ].indexed)
                _chip(m, selected: i == 0),
            ],
          ),
          const SizedBox(height: 6),
          const FieldLabel(
            '2. الشركة المصنّعة و Grade',
            icon: Icons.factory_outlined,
          ),
          _search('ابحث بالـ Grade أو الشركة'),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF5C46B)),
            ),
            child: const Row(
              children: [
                Icon(Icons.all_inclusive_rounded, color: Color(0xFF9A6200)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'أي شركة وأي Grade مقبول (مواصفات مفتوحة)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          option('PP500', 'SABIC', origins: 'السعودية', selected: true),
          option('129H', 'المتقدمة', origins: 'السعودية'),
          option('H030SG', 'Reliance', origins: 'الهند'),
          option('MARLEX 030', 'Chevron Phillips', pending: true),
          option('SG-5', 'الشركة غير محددة', unknownMaker: true),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة Grade غير موجود (يُراجع من المدير)'),
          ),
          const FieldLabel(
            '3. بلد الصنع (اختياري)',
            icon: Icons.public_rounded,
          ),
          Wrap(
            children: [
              _chip('غير محدد'),
              _chip('السعودية', selected: true),
              _chip('بلد آخر', icon: Icons.add_rounded),
            ],
          ),
        ],
      ),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _spec('PP · SABIC · PP500 · السعودية'),
            ),
            const SizedBox(height: 8),
            ActionPill(
              label: 'إضافة الخامة',
              icon: Icons.check_rounded,
              colors: ActionPill.blue,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------- تفاصيل: مواقع، مرفقات، تعديلات

class DetailsSectionsProposal extends StatelessWidget {
  const DetailsSectionsProposal({super.key});

  @override
  Widget build(BuildContext context) {
    Widget location(
      String kind,
      String address,
      String note, {
      bool isDefault = false,
      bool coords = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(kind, style: _bold)),
                if (isDefault) const Pill('افتراضي'),
              ],
            ),
            Text(address, style: _muted),
            Text(coords ? note : '$note • رابط بدون إحداثيات', style: _muted),
            const SizedBox(height: 6),
            Row(
              children: [
                _smallAction('الخريطة', Icons.map_rounded),
                _smallAction('نسخ', Icons.copy_rounded),
                _smallAction(
                  'مشاركة',
                  Icons.share_rounded,
                  color: AppColors.greenDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Widget tds(String grade, String file) => ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error),
      title: Align(
        alignment: AlignmentDirectional.centerStart,
        child: _spec(grade),
      ),
      subtitle: Text(file, style: _muted),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_rounded, color: AppColors.primary),
          SizedBox(width: 12),
          Icon(Icons.share_rounded, color: AppColors.greenDark),
        ],
      ),
    );

    Widget audit(String who, String when, String what) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_rounded, size: 18, color: AppColors.hint),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$what\n',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '$who • $when', style: _muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return CrmScaffold(
      title: 'بيانات المورد',
      icon: Icons.local_shipping_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SegmentTabs(
            labels: const ['نظرة عامة', 'التوريدات', 'التواصل', 'التفاصيل'],
            selected: 3,
            onChanged: (_) {},
          ),
          _section(
            'المواقع',
            Icons.place_rounded,
            trailing: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
              label: const Text('موقع'),
            ),
          ),
          location(
            'المخزن — موقع التحميل',
            'المنطقة الصناعية الثالثة، العاشر من رمضان',
            'البوابة 2، التحميل حتى 4 م',
            isDefault: true,
          ),
          location(
            'المقر الرئيسي',
            'شارع تجريبي، مدينة نصر',
            'الدور الثالث',
            coords: false,
          ),
          _section(
            'المرفقات',
            Icons.attach_file_rounded,
            trailing: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة'),
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('صور المنتجات', style: _bold),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: AppColors.fieldFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          i == 3 ? Icons.add_a_photo_outlined : Icons.image,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
                const Divider(height: 22),
                const Text('Technical Data Sheets', style: _bold),
                tds('PP · SABIC · PP500', 'TDS-PP500.pdf • 1.2 MB'),
                tds('PP · المتقدمة · 129H', 'TDS-129H.pdf • 0.8 MB'),
              ],
            ),
          ),
          _section('آخر التعديلات', Icons.manage_history_rounded),
          SectionCard(
            child: Column(
              children: [
                audit(
                  'أحمد محمد',
                  '28 أكتوبر 10:15 ص',
                  'أضاف خامة: PP · SABIC · PP500',
                ),
                audit('المدير', '27 أكتوبر 3:40 م', 'غيّر الهاتف الأساسي'),
                audit('أحمد محمد', '25 أكتوبر 9:02 ص', 'أنشأ السجل'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- إضافة موقع

class AddLocationProposal extends StatelessWidget {
  const AddLocationProposal({super.key});

  @override
  Widget build(BuildContext context) {
    Widget method(String label, IconData icon, {bool selected = false}) =>
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? Colors.white : AppColors.primary),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );

    return CrmScaffold(
      title: 'إضافة موقع',
      icon: Icons.add_location_alt_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const FieldLabel(
            'نوع الموقع',
            icon: Icons.category_rounded,
            required: true,
          ),
          Wrap(
            children: [
              _chip('المقر الرئيسي'),
              _chip('المصنع', selected: true),
              _chip('المخزن'),
              _chip('موقع التحميل'),
              _chip('موقع التسليم'),
            ],
          ),
          const FieldLabel('اسم وصفي', icon: Icons.label_outline_rounded),
          TextField(
            decoration: formDecoration(hint: 'مثال: مصنع العاشر - البوابة 2'),
          ),
          const SizedBox(height: 12),
          const FieldLabel('تحديد الموقع', icon: Icons.my_location_rounded),
          Row(
            children: [
              method('لصق رابط', Icons.link_rounded, selected: true),
              method('موقعي الحالي', Icons.gps_fixed_rounded),
              method('إحداثيات', Icons.pin_drop_outlined),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: TextEditingController(
              text: 'https://maps.google.com/?q=30.2950,31.7420',
            ),
            textDirection: TextDirection.ltr,
            decoration: formDecoration(),
          ),
          const SizedBox(height: 6),
          const InfoStrip(
            icon: Icons.check_circle_rounded,
            title: 'تم استخراج الإحداثيات: ',
            subtitle: '30.2950 , 31.7420',
            green: true,
          ),
          const SizedBox(height: 4),
          const Text(
            'الروابط المختصرة تُحفظ كما هي إن لم تحتوِ إحداثيات.',
            style: _muted,
          ),
          const SizedBox(height: 12),
          const FieldLabel('العنوان', icon: Icons.home_work_outlined),
          TextField(
            decoration: formDecoration(hint: 'المدينة، المنطقة، الشارع'),
          ),
          const SizedBox(height: 12),
          const FieldLabel('ملاحظات الوصول', icon: Icons.notes_rounded),
          TextField(decoration: formDecoration(hint: 'البوابة، المواعيد…')),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              value: true,
              onChanged: (_) {},
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'الموقع الافتراضي',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      bottom: SaveButton(label: 'حفظ الموقع', onPressed: () {}),
    );
  }
}

// ------------------------------------------------- إضافات الطلب والتوريد

class OrderAdditionsProposal extends StatelessWidget {
  const OrderAdditionsProposal({super.key});

  @override
  Widget build(BuildContext context) {
    Widget line(String spec, String qty, {bool open = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _spec(spec, color: open ? const Color(0xFFFFF1D6) : null),
                  if (open)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'مواصفات مفتوحة: أي شركة / أي Grade',
                        style: TextStyle(
                          color: Color(0xFF9A6200),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(qty, style: _bold),
            const SizedBox(width: 8),
            const Icon(Icons.delete_outline_rounded, color: AppColors.error),
          ],
        ),
      ),
    );

    return CrmScaffold(
      title: 'تسجيل طلب جديد',
      icon: Icons.assignment_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const FieldLabel('الخامات', icon: Icons.layers_rounded),
          line('PP · SABIC · PP500 · السعودية', '3 طن'),
          line('HDPE', '1 طن', open: true),
          Row(
            children: [
              Expanded(
                child: ActionPill(
                  label: 'إضافة خامة',
                  icon: Icons.add_rounded,
                  colors: ActionPill.blue,
                  outlined: true,
                  height: 46,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ActionPill(
                  label: 'تكرار بند سابق',
                  icon: Icons.replay_rounded,
                  colors: ActionPill.blue,
                  outlined: true,
                  height: 46,
                  onTap: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const FieldLabel('موقع التسليم', icon: Icons.local_shipping_outlined),
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المصنع (افتراضي)', style: _bold),
                      Text(
                        'المنطقة الصناعية الثالثة، العاشر من رمضان',
                        style: _muted,
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: () {}, child: const Text('تغيير')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ActionPill(
            label: 'إرسال للسائق',
            icon: Icons.share_rounded,
            colors: ActionPill.green,
            height: 50,
            onTap: () {},
          ),
          const SizedBox(height: 6),
          const Text(
            'يفتح قائمة المشاركة (WhatsApp أو غيره) برسالة: الخامات والكميات '
            'والعنوان ورابط الخريطة وملاحظات الوصول. لا يُرسل شيء تلقائيًا.',
            style: _muted,
          ),
        ],
      ),
      bottom: SaveButton(label: 'حفظ الطلب', onPressed: () {}),
    );
  }
}

// ----------------------------------------------------------- كتالوج الخامات

class CatalogProposal extends StatelessWidget {
  const CatalogProposal({super.key});

  @override
  Widget build(BuildContext context) {
    Widget grade(
      String code,
      String origins, {
      bool pending = false,
      String? by,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const SizedBox(width: 26),
          Text(
            code,
            textDirection: TextDirection.ltr,
            style: _bold.copyWith(fontSize: 14.5),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(by ?? origins, style: _muted)),
          if (pending) ...[
            _smallAction('اعتماد', Icons.verified_rounded),
            const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
          ] else
            const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
        ],
      ),
    );

    Widget maker(String name, List<Widget> grades) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.factory_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: _bold)),
                const Icon(Icons.add_rounded, color: AppColors.primary),
              ],
            ),
            ...grades,
          ],
        ),
      ),
    );

    return CrmScaffold(
      title: 'كتالوج الخامات',
      icon: Icons.inventory_2_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SegmentTabs(
            labels: const ['الخامات', 'الشركات', 'بانتظار التحقق (1)'],
            selected: 0,
            onChanged: (_) {},
          ),
          const SizedBox(height: 12),
          Wrap(
            children: [
              for (final (i, m) in ['PP', 'HDPE', 'LDPE', 'PVC'].indexed)
                _chip(m, selected: i == 0),
              _chip('خامة', icon: Icons.add_rounded),
            ],
          ),
          _search('ابحث في PP بالشركة أو Grade'),
          const SizedBox(height: 10),
          maker('SABIC', [
            grade('PP500', 'السعودية'),
            grade('PP520L', 'السعودية • هولندا'),
          ]),
          maker('المتقدمة', [grade('129H', 'السعودية')]),
          maker('Chevron Phillips', [
            grade(
              'MARLEX 030',
              '',
              pending: true,
              by: 'بانتظار التحقق • أضافه أحمد محمد',
            ),
          ]),
          maker('الشركة غير محددة (بيانات سابقة)', [
            grade('SG-5', 'يُربط بشركة يدويًا من المدير فقط'),
          ]),
        ],
      ),
    );
  }
}

final registryProposals = <String, Widget>{
  'registry': const RegistryProposal(),
  'material_picker': const MaterialPickerProposal(),
  'details_sections': const DetailsSectionsProposal(),
  'add_location': const AddLocationProposal(),
  'order_additions': const OrderAdditionsProposal(),
  'catalog': const CatalogProposal(),
};

void main() {
  for (final MapEntry(key: name, value: screen) in registryProposals.entries) {
    final size = name == 'details_sections'
        ? const Size(390, 1250)
        : referencePhone;
    testWidgets(
      'proposal $name',
      (tester) => withShadows(() async {
        await pumpScreen(tester, RepaintBoundary(child: screen), size: size);
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/proposal_${name}_390.png'),
        );
        if (Platform.environment['EXPORT_SCREENSHOTS'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            return data!.buffer.asUint8List();
          });
          Directory('../docs/phase4/proposals').createSync(recursive: true);
          File('../docs/phase4/proposals/proposal_$name.png')
              .writeAsBytesSync(bytes!);
        }
      }),
    );
  }
}
