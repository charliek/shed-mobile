// FRB de-risking spike: prove a Rust->Dart call into shed-core round-trips at
// RUNTIME on a real device (not just links). Calls the bridged shed_core
// probe and asserts its result, which forces the native lib to load and
// execute shed-core code (tokio async path + reqwest client build). (The
// shed_app probe went with the shed-app crate, plan 038: the phone links
// shed-core, shed-lane, shed-roost and shed-craze.)
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/src/rust/api/shed.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('shed_core_probe round-trips through the native lib', (_) async {
    final result = await shedCoreProbe(echo: 'spike');
    // ignore: avoid_print
    print('shedCoreProbe -> $result');
    expect(result, startsWith('shed-core ok: spike'));
    expect(result, contains('name_jitter(test,300000)='));
    expect(result, contains('reqwest_client_built=true'));
  });
}
