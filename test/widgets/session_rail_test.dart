import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/shed/shed_status.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_colors.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **The card's left edge, and what it is allowed to mean.**
///
/// The edge exists so a COLUMN reads at a glance — eight sessions as a strip of
/// colour, the ones asking for you finding you without any being read. That
/// only works if every row derives it from one rule, which is why this is a
/// pure function with its own test rather than a colour chosen per card.
void main() {
  final shed = shedLightTheme.extension<ShedColors>()!;

  Color? rail(
    BridgeRcState state, [
    BridgeRcActivity? activity,
    bool stale = false,
  ]) => sessionRailColor(shed, state, activity, stale: stale);

  test('a bad lifecycle outranks any activity', () {
    // A dead session is not merely idle, and a session that cannot authenticate
    // is not merely busy — so the lifecycle decides, whatever the activity says.
    expect(rail(BridgeRcState.dead, BridgeRcActivity.working), shed.dotErr);
    expect(rail(BridgeRcState.needsAuth, BridgeRcActivity.idle), shed.dotWarn);
    expect(rail(BridgeRcState.needsTrust, BridgeRcActivity.working), shed.dotWarn);
  });

  test('asking for a person outranks merely being busy', () {
    expect(rail(BridgeRcState.ready, BridgeRcActivity.needsInput), shed.dotWarn);
    expect(rail(BridgeRcState.ready, BridgeRcActivity.needsApproval), shed.dotWarn);
    expect(rail(BridgeRcState.ready, BridgeRcActivity.working), shed.dotOk);
  });

  test('nothing worth saying gets no edge at all', () {
    // An uncoloured row is the default, so the coloured ones carry weight. If
    // idle were a colour, a full list would be a wall of stripes saying nothing.
    expect(rail(BridgeRcState.ready, BridgeRcActivity.idle), isNull);
    expect(rail(BridgeRcState.ready), isNull);
    expect(rail(BridgeRcState.ready, BridgeRcActivity.unknown), isNull);
  });

  test('a stale row gets no edge, whatever it last said', () {
    // Its machine is unreachable: the row is the last KNOWN state, and colouring
    // it would assert something present about a box we cannot currently see.
    expect(rail(BridgeRcState.ready, BridgeRcActivity.needsInput, true), isNull);
    expect(rail(BridgeRcState.dead, BridgeRcActivity.working, true), isNull);
  });
}
