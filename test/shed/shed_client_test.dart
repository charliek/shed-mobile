import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/shed/shed_client.dart';

/// A PinnedHttpClient whose GET returns a canned body (no socket opened).
class _FakeHttp extends PinnedHttpClient {
  _FakeHttp(this._body) : super(host: 'x', port: 1, fingerprint: 'sha256:00');

  final String _body;

  @override
  Future<HttpResult> getJson(String path, {String? token}) async =>
      HttpResult(200, _body);

  @override
  void close() {}
}

class _FakeTokens implements TokenSource {
  @override
  Future<String?> get() async => 'tok';
  @override
  void invalidate(String token) {}
}

ShedClient _client(String body) => ShedClient(_FakeHttp(body), _FakeTokens());

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
}
