import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/core/sse_parser.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/rc/rc_events.dart';
import 'package:shed_mobile/shed/shed_client.dart';

/// A PinnedHttpClient seam: canned GET/POST bodies + a scripted SSE stream. This
/// mirrors how the JSON paths are faked (overriding getJson) — getSse is the SSE
/// analogue, so the client's typed decode + auth-retry logic is unit-tested
/// without a socket.
class _FakeHttp extends PinnedHttpClient {
  _FakeHttp({this.getResult, this.postResult, this.sse, this.sseError})
    : super(host: 'x', port: 1, fingerprint: 'sha256:00');

  HttpResult? getResult;
  HttpResult? postResult;
  Stream<SseRawEvent> Function(String? token)? sse;
  Object? sseError; // thrown on the FIRST getSse call, then cleared

  final getPaths = <String>[];
  final sseTokens = <String?>[];

  @override
  Future<HttpResult> getJson(String path, {String? token}) async {
    getPaths.add(path);
    return getResult ?? const HttpResult(200, '{}');
  }

  @override
  Future<HttpResult> postJson(
    String path, {
    Object? body,
    String? token,
  }) async => postResult ?? const HttpResult(200, '{"delivered":true}');

  @override
  Stream<SseRawEvent> getSse(String path, {String? token}) {
    sseTokens.add(token);
    final err = sseError;
    if (err != null) {
      sseError = null; // only the first attempt fails
      return Stream<SseRawEvent>.error(err);
    }
    return sse?.call(token) ?? const Stream<SseRawEvent>.empty();
  }

  @override
  void close() {}
}

class _StaticTokens implements TokenSource {
  @override
  Future<String?> get() async => 'tok';
  @override
  void invalidate(String token) {}
}

/// Yields a fresh token after invalidate, so the 401-retry path can distinguish
/// the rejected token from its replacement.
class _RotatingTokens implements TokenSource {
  int _n = 0;
  final invalidated = <String>[];
  @override
  Future<String?> get() async => 'tok$_n';
  @override
  void invalidate(String token) {
    invalidated.add(token);
    _n++;
  }
}

void main() {
  group('ShedClient.rcEvents', () {
    test(
      'decodes SSE frames into typed events, dropping unknown/comment',
      () async {
        final http = _FakeHttp(
          sse: (_) => Stream.fromIterable([
            const SseRawEvent(
              'activity.changed',
              '{"shed":"p","slug":"a","activity":"working","state":"ready"}',
            ),
            const SseRawEvent('heartbeat', ''), // dropped
            const SseRawEvent(
              'message.appended',
              '{"shed":"p","slug":"a","seq":3}',
            ),
          ]),
        );
        final client = ShedClient(http, _StaticTokens());
        final events = await client.rcEvents().toList();
        expect(events, hasLength(2));
        expect(events[0], isA<RcActivityChanged>());
        expect((events[1] as RcMessageAppended).seq, 3);
      },
    );

    test(
      'a 401 on stream-open invalidates + retries once with a fresh token',
      () async {
        final tokens = _RotatingTokens();
        final http = _FakeHttp(
          sseError: AppError('SHED_UNAUTHORIZED', 'nope', 401),
          sse: (_) => Stream.fromIterable([
            const SseRawEvent('shed.stopped', '{"shed":"p"}'),
          ]),
        );
        final client = ShedClient(http, tokens);
        final events = await client.rcEvents().toList();
        expect(events, hasLength(1));
        expect(events.single, isA<RcShedStopped>());
        // First attempt used tok0 (rejected), retry used the rotated tok1.
        expect(tokens.invalidated, ['tok0']);
        expect(http.sseTokens, ['tok0', 'tok1']);
      },
    );
  });

  group('ShedClient.fetchRcMessages', () {
    test('builds the proxied since/limit path and decodes the page', () async {
      final http = _FakeHttp(
        getResult: const HttpResult(
          200,
          '{"messages":[{"seq":6,"role":"assistant","type":"text","text":"hi"}],"truncated":true}',
        ),
      );
      final client = ShedClient(http, _StaticTokens());
      final page = await client.fetchRcMessages(
        'proj',
        'cdx777',
        since: 5,
        limit: 200,
      );
      expect(
        http.getPaths.single,
        '/api/sheds/proj/rc/v1/sessions/cdx777/messages?since=5&limit=200',
      );
      expect(page.truncated, isTrue);
      expect(page.messages.single.seq, 6);
    });
  });

  group('ShedClient.postRcInput', () {
    test('2xx delivers with no throw', () async {
      final client = ShedClient(
        _FakeHttp(postResult: const HttpResult(200, '{"delivered":true}')),
        _StaticTokens(),
      );
      await client.postRcInput('proj', 'cdx777', 'hello'); // no throw
    });

    test(
      '409 → RC_NOT_ACCEPTING (the input-race the caller refreshes on)',
      () async {
        final client = ShedClient(
          // The hub's flat {error,message} body; classification keys off status.
          _FakeHttp(
            postResult: const HttpResult(
              409,
              '{"error":"not_accepting","message":"session is not waiting for input"}',
            ),
          ),
          _StaticTokens(),
        );
        await expectLater(
          client.postRcInput('proj', 'cdx777', 'hello'),
          throwsA(
            isA<AppError>()
                .having((e) => e.code, 'code', 'RC_NOT_ACCEPTING')
                .having((e) => e.statusCode, 'status', 409),
          ),
        );
      },
    );

    test('503 → RC_HUB_UNAVAILABLE (server nested error shape)', () async {
      final client = ShedClient(
        _FakeHttp(
          postResult: const HttpResult(
            503,
            '{"error":{"code":"RC_HUB_UNAVAILABLE","message":"rc hub is not available"}}',
          ),
        ),
        _StaticTokens(),
      );
      await expectLater(
        client.postRcInput('proj', 'cdx777', 'hello'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', 'RC_HUB_UNAVAILABLE')
              .having((e) => e.statusCode, 'status', 503),
        ),
      );
    });
  });
}
