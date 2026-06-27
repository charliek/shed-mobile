import 'dart:convert';

import 'package:flutter/material.dart';

import '../../theme/shed_colors.dart';

/// One virtual key in the terminal toolbar: an id, a label, and the bytes it
/// sends to the PTY.
typedef TerminalKey = ({String id, String label, List<int> bytes});

/// The keys a phone soft keyboard typically lacks. Bytes mirror the web
/// TerminalKeys (xterm escape sequences). Pure data — unit-tested.
const List<TerminalKey> terminalKeys = [
  (id: 'esc', label: 'Esc', bytes: [0x1b]),
  (id: 'tab', label: 'Tab', bytes: [0x09]),
  (id: 'up', label: '↑', bytes: [0x1b, 0x5b, 0x41]),
  (id: 'down', label: '↓', bytes: [0x1b, 0x5b, 0x42]),
  (id: 'left', label: '←', bytes: [0x1b, 0x5b, 0x44]),
  (id: 'right', label: '→', bytes: [0x1b, 0x5b, 0x43]),
  (id: 'c', label: '^C', bytes: [0x03]),
  (id: 'd', label: '^D', bytes: [0x04]),
  (id: 'l', label: '^L', bytes: [0x0c]),
  (id: 'pgup', label: 'PgUp', bytes: [0x1b, 0x5b, 0x35, 0x7e]),
  (id: 'pgdn', label: 'PgDn', bytes: [0x1b, 0x5b, 0x36, 0x7e]),
  (id: 'home', label: 'Home', bytes: [0x1b, 0x5b, 0x48]),
  (id: 'end', label: 'End', bytes: [0x1b, 0x5b, 0x46]),
];

/// Sticky-Ctrl: when [armed], turn a single ASCII letter into its control code
/// (`& 0x1f`); anything else — multi-rune, IME-composed text, paste, escape
/// reports — passes through unchanged, so a stray armed state can't mangle a
/// paste or a terminal response. Returns the bytes to write; the caller disarms
/// on any input.
List<int> applyStickyCtrl({required bool armed, required String data}) {
  if (armed && data.length == 1) {
    final c = data.codeUnitAt(0);
    if ((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)) return [c & 0x1f];
  }
  return utf8.encode(data);
}

/// A horizontally-scrolling toolbar of virtual keys above the terminal. Wrapped
/// in [ExcludeFocus] so tapping a key can't steal focus from the terminal — the
/// soft keyboard stays up (the Flutter analog of the web's preventDefault).
class TerminalKeys extends StatelessWidget {
  const TerminalKeys({
    super.key,
    required this.ctrlArmed,
    required this.onToggleCtrl,
    required this.onKey,
  });

  final bool ctrlArmed;
  final VoidCallback onToggleCtrl;
  final void Function(List<int> bytes) onKey;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return ExcludeFocus(
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: shed.surface,
          border: Border(top: BorderSide(color: shed.line)),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          children: [
            _KeyButton(
              key: const ValueKey('term-key-ctrl'),
              label: ctrlArmed ? 'Ctrl •' : 'Ctrl',
              filled: ctrlArmed,
              onTap: onToggleCtrl,
            ),
            for (final k in terminalKeys)
              _KeyButton(
                key: ValueKey('term-key-${k.id}'),
                label: k.label,
                onTap: () => onKey(k.bytes),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  static const _style = ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
    minimumSize: WidgetStatePropertyAll(Size(0, 32)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: filled
          ? FilledButton(onPressed: onTap, style: _style, child: child)
          : OutlinedButton(onPressed: onTap, style: _style, child: child),
    );
  }
}
