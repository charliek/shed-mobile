import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/shed/shed_client.dart';

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
  group('listSheds parsing', () {
    test('a nil slice ({"sheds":null}) is an empty list, not an error', () async {
      // Go marshals an empty slice as null; a host with no sheds must not crash.
      expect(await _client('{"sheds":null}').listSheds(), isEmpty);
    });

    test('missing key is an empty list', () async {
      expect(await _client('{}').listSheds(), isEmpty);
    });

    test('a populated list parses', () async {
      final sheds = await _client(
        '{"sheds":[{"name":"a","status":"running"},{"name":"b","status":"stopped"}]}',
      ).listSheds();
      expect(sheds.map((s) => s.name), ['a', 'b']);
      expect(sheds.first.isRunning, isTrue);
    });

    test('a top-level array parses', () async {
      final sheds = await _client(
        '[{"name":"a","status":"running"}]',
      ).listSheds();
      expect(sheds, hasLength(1));
    });

    test(
      'a wrong-typed value (not null, not a list) is a parse error',
      () async {
        await expectLater(
          _client('{"sheds":42}').listSheds(),
          throwsA(
            isA<AppError>().having((e) => e.code, 'code', 'SHED_PARSE_ERROR'),
          ),
        );
      },
    );
  });

  group('getSystemDf parsing', () {
    test('totals parse (physical bytes is the rendered field)', () async {
      final df = await _client(
        '{"server_name":"mac-mini","backend":"vz","totals":'
        '{"all":{"logical_bytes":71,"physical_bytes":14506430464},'
        '"images":{"physical_bytes":1323184128}}}',
      ).getSystemDf();
      expect(df.serverName, 'mac-mini');
      expect(df.backend, 'vz');
      expect(df.totals.all.physicalBytes, 14506430464);
      expect(df.totals.images.physicalBytes, 1323184128);
      expect(df.totals.snapshots.physicalBytes, 0); // absent → zero
    });

    test('a missing totals block yields zeros (tolerant)', () async {
      final df = await _client('{"server_name":"x"}').getSystemDf();
      expect(df.totals.all.physicalBytes, 0);
    });

    test(
      'an old agent (404) surfaces as an AppError the UI can catch',
      () async {
        await expectLater(
          _client(
            '{"error":{"code":"NOT_FOUND","message":"no df"}}',
            404,
          ).getSystemDf(),
          throwsA(isA<AppError>()),
        );
      },
    );
  });
}
