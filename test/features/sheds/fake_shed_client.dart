import 'dart:async';

import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/src/rust/api/error.dart';

/// A recording [BridgeClient] fake shared by the shed_card and
/// shed_list_screen tests: every lifecycle action is appended to [calls] as
/// `<verb>:<name>` (order-preserving, so restart's stop-then-start is
/// assertable). [listSheds] serves [sheds] while counting fetches, so a
/// re-fetch triggered by `invalidateShedViews` is observable. `noSuchMethod`
/// guards any accidental other call.
class FakeShedClient implements BridgeClient {
  FakeShedClient({
    this.sheds = const [],
    this.cloudUsage,
    this.extendOutcome,
    this.extendGate,
  });

  /// When set, [extend] waits for it before answering.
  final Completer<void>? extendGate;

  final List<BridgeShed> sheds;

  /// What [usage] answers; null throws as a server without cloud sheds does.
  final BridgeCloudUsage? cloudUsage;

  /// What [extend] answers (recorded as `extend:<name>:<hours>`).
  final BridgeExtendOutcome? extendOutcome;
  final List<String> calls = [];
  int listShedsCalls = 0;
  int overviewCalls = 0;

  int get starts => calls.where((c) => c.startsWith('start:')).length;
  int get stops => calls.where((c) => c.startsWith('stop:')).length;
  int get deletes => calls.where((c) => c.startsWith('delete:')).length;

  @override
  Future<void> start({required String name}) async => calls.add('start:$name');
  @override
  Future<void> stop({required String name}) async => calls.add('stop:$name');
  @override
  Future<void> delete({required String name}) async =>
      calls.add('delete:$name');
  @override
  Future<List<BridgeShed>> listSheds() async {
    listShedsCalls++;
    return sheds;
  }

  @override
  Future<BridgeOverview> overview() async {
    overviewCalls++;
    return BridgeOverview(
      server: const BridgeOverviewServer(version: '1', features: []),
      sheds: [
        for (final s in sheds) BridgeOverviewShed(shed: s, sessions: const []),
      ],
      warnings: const [],
    );
  }

  @override
  Future<BridgeCloudUsage> usage() async {
    final u = cloudUsage;
    if (u == null) throw const BridgeError.badStatus(code: 501);
    return u;
  }

  @override
  Future<BridgeExtendOutcome> extend({
    required String name,
    required int hours,
  }) async {
    calls.add('extend:$name:$hours');
    await extendGate?.future;
    return extendOutcome ??
        BridgeExtendOutcome.extended(
          shed: sheds.firstWhere((s) => s.name == name),
        );
  }

  @override
  void dispose() {}
  @override
  bool get isDisposed => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
