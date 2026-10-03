import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/profile/data/bd_districts.dart';

/// Searchable bottom sheet with all 64 districts. Returns the Bangla name
/// (the stored value), or null when dismissed.
Future<String?> showDistrictPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => _DistrictList(selected: selected, controller: controller),
    ),
  );
}

class _DistrictList extends StatefulWidget {
  const _DistrictList({required this.selected, required this.controller});
  final String? selected;
  final ScrollController controller;

  @override
  State<_DistrictList> createState() => _DistrictListState();
}

class _DistrictListState extends State<_DistrictList> {
  final _search = TextEditingController();
  List<(String, String)> _items = bdDistricts;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bangla = context.isBn;
    final current = findDistrict(widget.selected);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (q) => setState(() => _items = searchDistricts(q)),
            decoration: InputDecoration(
              hintText: l.profileDistrictSearch,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Text(l.profileDistrictNone))
              : ListView.builder(
                  controller: widget.controller,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final d = _items[i];
                    final isSelected = current == d;
                    return ListTile(
                      title: Text(bangla ? d.$1 : d.$2),
                      subtitle: Text(bangla ? d.$2 : d.$1),
                      trailing: isSelected ? Icon(Icons.check_circle_rounded, color: scheme.primary) : null,
                      selected: isSelected,
                      onTap: () => Navigator.of(context).pop(d.$1),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
