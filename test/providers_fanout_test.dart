import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/shed/shed_client.dart';

/// A PinnedHttpClient returning a canned (status, body) for any GET — no socket.
class _FakeHttp extends PinnedHttpClient {
  _FakeHttp(this.status, this.body)
    : super(host: 'x', port: 1, fingerprint: 'sha256:00');
  final int status;
  final String body;
  @override
  Future<HttpResult> getJson(String path, {String? token}) async =>
      HttpResult(status, body);
  @override
  void close() {}
}

class _FakeTokens implements TokenSource {
  @override
  Future<String?> get() async => 'tok';
  @override
  void invalidate(String token) {}
}

ShedClient _client(int status, String body) =>
    ShedClient(_FakeHttp(status, body), _FakeTokens());

void main() {
  // Per-host *UI* isolation (one offline host still lets the others render) is
  // exercised at the widget level in P3–P5, where each host group owns its own
  // AsyncValue. Here we cover the provider wiring: it resolves a host's usage via
  // the (overridable) client, and an old agent's 404 surfaces as an AppError the
  // section can catch per host (asserted at the client level in shed_client_test).
  test(
    'hostSystemDfProvider resolves a host\'s disk usage via the client',
    () async {
      final container = ProviderContainer(
        overrides: [
          shedClientProvider.overrideWith(
            (ref, name) async => _client(
              200,
              '{"server_name":"$name","backend":"vz",'
              '"totals":{"all":{"physical_bytes":1024}}}',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(hostSystemDfProvider('mac-mini'), (_, _) {});

      final df = await container.read(hostSystemDfProvider('mac-mini').future);
      expect(df.serverName, 'mac-mini');
      expect(df.totals.all.physicalBytes, 1024);
    },
  );

  test(
    'hostSessionsProvider returns rc rows only (plain tmux filtered out)',
    () async {
      final container = ProviderContainer(
        overrides: [
          shedClientProvider.overrideWith(
            (ref, name) async => _client(
              200,
              '[{"name":"rc-aaa","shed_name":"s","rc":{"kind":"claude-rc","state":"ready"}},'
              '{"name":"plain","shed_name":"s"}]',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(hostSessionsProvider('h'), (_, _) {});

      final sessions = await container.read(hostSessionsProvider('h').future);
      expect(sessions, hasLength(1));
      expect(sessions.first.name, 'rc-aaa');
      expect(sessions.first.isRc, isTrue);
    },
  );
}
