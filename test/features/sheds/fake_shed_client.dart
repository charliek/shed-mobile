import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';

/// A recording [BridgeClient] fake shared by the shed_card and
/// shed_list_screen tests: every lifecycle action is appended to [calls] as
/// `<verb>:<name>` (order-preserving, so restart's stop-then-start is
/// assertable). [listSheds] serves [sheds] while counting fetches, so a
/// re-fetch triggered by `invalidateShedViews` is observable. `noSuchMethod`
/// guards any accidental other call.
class FakeShedClient implements BridgeClient {
  FakeShedClient({this.sheds = const []});

  final List<BridgeShed> sheds;
  final List<String> calls = [];
  int listShedsCalls = 0;

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
  void dispose() {}
  @override
  bool get isDisposed => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
