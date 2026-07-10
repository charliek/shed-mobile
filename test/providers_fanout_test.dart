import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/shed/shed_client.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';

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

String _goldenOverview() =>
    File('test/shed/testdata/overview.golden.json').readAsStringSync();

/// A container whose shedClientProvider is overridden to a canned response.
/// Auto-retry is disabled so an errored (e.g. 404) provider settles to a stable
/// error the read completes with, instead of Riverpod 3 retrying it forever.
ProviderContainer _container(int status, String body) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      shedClientProvider.overrideWith(
        (ref, name) async => _client(status, body),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // The former per-shed SSH fan-out (hostSessionsProvider) + hostSystemDfProvider
  // are gone: the Hosts and Sessions views now compose a single GET /api/overview
  // per host. These cover the overview-derived provider wiring; per-host UI
  // isolation stays a widget/drive concern.

  test('overviewProvider resolves a host snapshot via the client', () async {
    final container = _container(200, _goldenOverview());
    container.listen(overviewProvider('h'), (_, _) {});
    final r = await container.read(overviewProvider('h').future);
    final o = (r as OverviewData).overview;
    expect(o.server.version, '0.8.0');
    expect(o.df!.serverName, 'test-server');
    expect(o.sheds, hasLength(2));
  });

  test('a 404 overview resolves to the TERMINAL OverviewUnsupported value '
      '(a value, not a retryable error)', () async {
    final container = _container(404, 'not found');
    container.listen(overviewProvider('old'), (_, _) {});
    final r = await container.read(overviewProvider('old').future);
    expect(r, isA<OverviewUnsupported>());
  });

  test('shedSessionPairs flattens the overview into (shed, session) pairs '
      '(only rc-enriched rows; stopped shed contributes none)', () async {
    final container = _container(200, _goldenOverview());
    container.listen(overviewProvider('h'), (_, _) {});
    final r = await container.read(overviewProvider('h').future);
    final list = shedSessionPairs((r as OverviewData).overview);
    // proj: two rc rows; the plain "default" row and the stopped "asleep" shed
    // contribute nothing.
    expect(list.map((e) => e.session.slug), ['abc234', 'cdx777']);
    expect(list.every((e) => e.shedName == 'proj'), isTrue);
    expect(list[1].session.kind, RcKind.codex);
  });

  test(
    'shedCapabilitiesProvider extracts one shed\'s caps from the overview',
    () async {
      final container = _container(200, _goldenOverview());
      final key = (serverName: 'h', shedName: 'proj');
      container.listen(shedCapabilitiesProvider(key), (_, _) {});
      final caps = await container.read(shedCapabilitiesProvider(key).future);
      expect(caps, isNotNull);
      expect(caps!.offers(RcKind.codex), isTrue);
    },
  );

  test(
    'shedCapabilitiesProvider yields null for a stopped/absent-caps shed',
    () async {
      final container = _container(200, _goldenOverview());
      final key = (serverName: 'h', shedName: 'asleep');
      container.listen(shedCapabilitiesProvider(key), (_, _) {});
      expect(
        await container.read(shedCapabilitiesProvider(key).future),
        isNull,
      );
    },
  );

  test(
    'shedCapabilitiesProvider yields null on an old server (404 → absent)',
    () async {
      final container = _container(404, 'not found');
      final key = (serverName: 'old', shedName: 'proj');
      container.listen(shedCapabilitiesProvider(key), (_, _) {});
      expect(
        await container.read(shedCapabilitiesProvider(key).future),
        isNull,
      );
    },
  );

  testWidgets(
    'invalidateShedViews refetches BOTH the shed list and the overview '
    '(shed lifecycle/create paths must not leave the Hosts/Sessions views stale)',
    (tester) async {
      var shedBuilds = 0;
      var overviewBuilds = 0;
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shedsProvider.overrideWith((ref, name) async {
              shedBuilds++;
              return const <Shed>[];
            }),
            overviewProvider.overrideWith((ref, name) async {
              overviewBuilds++;
              return const OverviewUnsupported();
            }),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                ref.watch(shedsProvider('h'));
                ref.watch(overviewProvider('h'));
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(shedBuilds, 1);
      expect(overviewBuilds, 1);

      invalidateShedViews(widgetRef, 'h');
      await tester.pumpAndSettle();
      expect(shedBuilds, 2);
      expect(overviewBuilds, 2);
    },
  );
}
