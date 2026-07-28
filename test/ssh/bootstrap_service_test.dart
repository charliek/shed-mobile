import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/servers/server_target.dart';
import 'package:shed_mobile/ssh/bootstrap_service.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/ssh_runner.dart';

/// A real standard-base64 CSR shape: `+`, `/` and `=` padding all present, which
/// is the whole point — none of them is bare-safe under `shellQuote`, so a
/// quoting layer anywhere on this path is immediately visible here.
const _csr = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+t/9abc+DEF/ghi==';

ServerTarget _target() => const ServerTarget(
  name: 'mini3',
  host: 'mini3.example',
  sshPort: 2222,
  secure: true,
  baseUrl: 'https://mini3.example',
);

/// Captures the composed wire command instead of dialling SSH.
class _CapturingRun {
  String? command;
  Duration? timeout;
  String stdout = '{"scope":"control"}';

  Future<SshResult> call(
    String command, {
    String? stdin,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    this.command = command;
    this.timeout = timeout;
    return SshResult(0, stdout, '');
  }
}

BootstrapService _service(_CapturingRun run) =>
    BootstrapService(const [], HostKeyStore(), runWire: run.call);

void main() {
  group('the _bootstrap request line', () {
    test('appends a CSR VERBATIM — unquoted, exactly one argument', () async {
      final run = _CapturingRun();
      await _service(run).mintRaw(_target(), extraArgs: ['csr=$_csr']);

      // The EXACT wire shape, spelled out: `<scope> <kind> csr=<std base64>`.
      // shed-server reads this with sess.RawCommand() and splits it on
      // whitespace — no shell — so a POSIX-quoted `'csr=…'` would arrive WITH
      // the quotes, miss the `csr=` prefix match, and make an mtls server answer
      // "this server requires auth.mode: mtls; upgrade shed".
      expect(run.command, 'control shed-mobile csr=$_csr');
      expect(run.command, isNot(contains("'")));
      expect(run.command!.split(' '), ['control', 'shed-mobile', 'csr=$_csr']);
      expect(
        run.command!.split(' ').where((a) => a.startsWith('csr=')).length,
        1,
      );
    });

    test('a CSR-less mint is byte-identical to the pre-mtls line', () async {
      final run = _CapturingRun();
      await _service(run).mintRaw(_target());
      // plan 001 D4 compat leg: a released server sees exactly what it always saw.
      expect(run.command, 'control shed-mobile');
    });

    test('rides the 15s SSH bound (below both Rust mint timeouts)', () async {
      final run = _CapturingRun();
      await _service(run).mintRaw(_target());
      expect(run.timeout, const Duration(seconds: 15));
      expect(BootstrapService.timeout, const Duration(seconds: 15));
    });

    test('rejects an argument that would split the line', () {
      // Defence in depth: nothing downstream quotes these, so a whitespace-
      // bearing token would silently become two wire arguments.
      expect(
        () => BootstrapService.requestLine(['csr=a b']),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'BOOTSTRAP_BAD_ARG'),
        ),
      );
      expect(
        () => BootstrapService.requestLine(['']),
        throwsA(isA<AppError>()),
      );
    });
  });

  test('empty stdout is a typed failure that echoes nothing', () async {
    final run = _CapturingRun()..stdout = '   ';
    await expectLater(
      _service(run).mintRaw(_target()),
      throwsA(
        isA<AppError>().having((e) => e.code, 'code', 'SHED_AUTH_EXPIRED'),
      ),
    );
  });
}
