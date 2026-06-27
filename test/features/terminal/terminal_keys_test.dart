import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/terminal/terminal_keys.dart';

void main() {
  group('terminalKeys map', () {
    test('has the expected keys with correct escape sequences', () {
      final byId = {for (final k in terminalKeys) k.id: k.bytes};
      expect(byId['esc'], [0x1b]);
      expect(byId['tab'], [0x09]);
      expect(byId['up'], [0x1b, 0x5b, 0x41]);
      expect(byId['down'], [0x1b, 0x5b, 0x42]);
      expect(byId['left'], [0x1b, 0x5b, 0x44]);
      expect(byId['right'], [0x1b, 0x5b, 0x43]);
      expect(byId['c'], [0x03]); // Ctrl-C
      expect(byId['d'], [0x04]); // Ctrl-D
      expect(byId['l'], [0x0c]); // Ctrl-L
      expect(byId['pgup'], [0x1b, 0x5b, 0x35, 0x7e]);
      expect(byId['pgdn'], [0x1b, 0x5b, 0x36, 0x7e]);
      expect(byId['home'], [0x1b, 0x5b, 0x48]);
      expect(byId['end'], [0x1b, 0x5b, 0x46]);
    });

    test('every key has a unique id and non-empty bytes', () {
      final ids = terminalKeys.map((k) => k.id).toSet();
      expect(ids.length, terminalKeys.length);
      for (final k in terminalKeys) {
        expect(k.bytes, isNotEmpty, reason: k.id);
        expect(k.label, isNotEmpty, reason: k.id);
      }
    });
  });

  group('applyStickyCtrl', () {
    test('not armed: data passes through unchanged', () {
      expect(applyStickyCtrl(armed: false, data: 'a'), [0x61]);
    });

    test('armed + single lowercase letter -> control code', () {
      expect(applyStickyCtrl(armed: true, data: 'c'), [0x03]); // ^C
    });

    test('armed + single uppercase letter -> control code', () {
      expect(applyStickyCtrl(armed: true, data: 'C'), [0x03]);
      expect(applyStickyCtrl(armed: true, data: 'A'), [0x01]);
      expect(applyStickyCtrl(armed: true, data: 'Z'), [0x1a]);
    });

    test('armed + non-letter passes through', () {
      expect(applyStickyCtrl(armed: true, data: '1'), [0x31]);
    });

    test('armed + multi-char (paste/IME) passes through unchanged', () {
      expect(applyStickyCtrl(armed: true, data: 'hello'), 'hello'.codeUnits);
    });

    test('armed + escape sequence passes through (not mangled)', () {
      expect(applyStickyCtrl(armed: true, data: '\x1b[A'), [0x1b, 0x5b, 0x41]);
    });
  });
}
