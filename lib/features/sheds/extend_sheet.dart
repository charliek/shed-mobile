import 'package:flutter/material.dart';

import '../../src/rust/api/dto.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';

/// Ask how many hours to extend a cloud shed's lease by (plan 041): the
/// server's presets, already clipped to the cap by the bridge, or a custom
/// number of hours from 1 to [BridgeShedLease.extendMaxH]. Resolves to the
/// hours chosen, or null when dismissed.
Future<int?> showExtendSheet(
  BuildContext context, {
  required String name,
  required BridgeShedLease lease,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ExtendSheet(name: name, lease: lease),
);

class ExtendSheet extends StatefulWidget {
  const ExtendSheet({required this.name, required this.lease, super.key});

  final String name;
  final BridgeShedLease lease;

  @override
  State<ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends State<ExtendSheet> {
  final _custom = TextEditingController();
  int? _preset;

  int get _max => widget.lease.extendMaxH;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// The hours to send: the custom field when it has text, else the preset.
  int? get _hours {
    final text = _custom.text.trim();
    if (text.isEmpty) return _preset;
    final h = int.tryParse(text);
    return (h != null && h >= 1 && h <= _max) ? h : null;
  }

  String? get _customError {
    final text = _custom.text.trim();
    if (text.isEmpty || _hours != null) return null;
    return 'A whole number of hours from 1 to $_max';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final hours = _hours;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const ValueKey('extend-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extend ${widget.name}',
            style: sansStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Moves the lease later by the hours chosen, up to $_max h '
            '(its cap).',
            style: sansStyle(fontSize: 13, color: c.fg2),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in widget.lease.extendPresetsH)
                ChoiceChip(
                  key: ValueKey('extend-preset-$h'),
                  label: Text('$h h'),
                  selected: _custom.text.trim().isEmpty && _preset == h,
                  onSelected: (_) => setState(() {
                    _preset = h;
                    _custom.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('extend-hours'),
            controller: _custom,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Custom hours',
              errorText: _customError,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('extend-submit'),
              onPressed: hours == null
                  ? null
                  : () => Navigator.of(context).pop(hours),
              child: Text(hours == null ? 'Extend' : 'Extend by $hours h'),
            ),
          ),
        ],
      ),
    );
  }
}
