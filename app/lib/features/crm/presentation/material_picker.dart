import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/crm_models.dart';

/// قائمة اختيار الخامات (اختيار متعدد) من القوائم الأساسية.
Future<List<String>?> pickMaterials(
  BuildContext context, {
  required List<MaterialItem> materials,
  required List<String> selected,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _MaterialSheet(materials: materials, initial: selected),
  );
}

class _MaterialSheet extends StatefulWidget {
  const _MaterialSheet({required this.materials, required this.initial});

  final List<MaterialItem> materials;
  final List<String> initial;

  @override
  State<_MaterialSheet> createState() => _MaterialSheetState();
}

class _MaterialSheetState extends State<_MaterialSheet> {
  late final _selected = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'اختر الخامات',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in widget.materials)
                    CheckboxListTile(
                      key: Key('material.${m.code}'),
                      value: _selected.contains(m.id),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _selected.add(m.id)
                            : _selected.remove(m.id),
                      ),
                      title: Text(
                        m.code,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(m.nameAr),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('material.done'),
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: const Text('تم'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
