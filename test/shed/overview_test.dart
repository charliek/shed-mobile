import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/shed/shed_client.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';

/// A PinnedHttpClient whose GET returns a canned (status, body) — no socket.
class _FakeHttp extends PinnedHttpClient {
  _FakeHttp(this._body, [this._status = 200])
    : super(host: 'x', port: 1, fingerprint: 'sha256:00');

  final String _body;
  final int _status;

  @override
  Future<HttpResult> getJson(String path, {String? token}) async =>
      HttpResult(_status, _body);

  @override
  void close() {}
}

class _FakeTokens implements TokenSource {
  @override
  Future<String?> get() async => 'tok';
  @override
  void invalidate(String token) {}
}

ShedClient _client(String body, [int status = 200]) =>
    ShedClient(_FakeHttp(body, status), _FakeTokens());

void main() {
  group('Overview.fromJson (golden GET /api/overview)', () {
    late Overview overview;

    setUp(() {
      final raw = File(
        'test/shed/testdata/overview.golden.json',
      ).readAsStringSync();
      overview = Overview.fromJson(jsonDecode(raw) as Map<String, Object?>);
    });

    test('server block: version + feature tokens', () {
      expect(overview.server.version, '0.8.0');
      expect(overview.server.hasFeature('overview'), isTrue);
      expect(overview.server.hasFeature('rc-enrich'), isTrue);
    });

    test('df block parses (physical bytes is the rendered field)', () {
      expect(overview.df, isNotNull);
      expect(overview.df!.serverName, 'test-server');
      expect(overview.df!.backend, 'vz');
      expect(overview.df!.totals.all.physicalBytes, 14506430464);
    });

    test('a running shed carries only its rc-enriched sessions', () {
      final proj = overview.sheds.firstWhere((s) => s.shed.name == 'proj');
      expect(proj.shed.isRunning, isTrue);
      // The plain "default" tmux row (no rc block) is dropped; the two rc rows
      // remain, with slug/tmux derived from the session name.
      expect(proj.sessions.map((s) => s.slug), ['abc234', 'cdx777']);
      final claude = proj.sessions[0];
      expect(claude.tmuxSession, 'rc-abc234');
      expect(claude.kind, RcKind.claudeRc);
      expect(claude.state, RcState.ready);
      expect(claude.managed, isTrue);
      expect(claude.hasUrl, isTrue);
      expect(claude.displayName, 'proj/abc234');
      // Second row: the new codex kind, needs-auth, no url.
      final codex = proj.sessions[1];
      expect(codex.kind, RcKind.codex);
      expect(codex.state, RcState.needsAuth);
      expect(codex.hasUrl, isFalse);
    });

    test('a running shed carries its rc capabilities', () {
      final proj = overview.sheds.firstWhere((s) => s.shed.name == 'proj');
      final caps = proj.capabilities;
      expect(caps, isNotNull);
      expect(caps!.rcVersion, 3);
      // codex advertised + installed → offered; opencode not installed → not.
      expect(caps.offers(RcKind.codex), isTrue);
      expect(caps.creatableKinds(), contains(RcKind.codex));
      expect(caps.offers(RcKind.opencode), isFalse);
    });

    test('a stopped shed has no sessions and ABSENT capabilities', () {
      final asleep = overview.sheds.firstWhere((s) => s.shed.name == 'asleep');
      expect(asleep.shed.isRunning, isFalse);
      expect(asleep.sessions, isEmpty);
      expect(asleep.capabilities, isNull); // absent → tolerated
    });
  });

  group('ShedClient.fetchOverview', () {
    test('decodes a 200 overview body', () async {
      final raw = File(
        'test/shed/testdata/overview.golden.json',
      ).readAsStringSync();
      final overview = await _client(raw).fetchOverview();
      expect(overview.sheds, hasLength(2));
    });

    test('a 404 (old server) surfaces as an AppError the provider can map', () {
      expect(
        _client('not found', 404).fetchOverview(),
        throwsA(isA<AppError>().having((e) => e.statusCode, 'status', 404)),
      );
    });
  });
}
