import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/rc_events.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/shed/shed_client.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';

class _NoHttp extends PinnedHttpClient {
  _NoHttp() : super(host: 'x', port: 1, fingerprint: 'sha256:00');
  @override
  void close() {}
}

class _Tok implements TokenSource {
  @override
  Future<String?> get() async => null;
  @override
  void invalidate(String token) {}
}

/// A ShedClient whose rcEvents() returns each scripted stream in turn — so the
/// provider's reconnect loop is driven deterministically. [connects] counts
/// rcEvents() calls (the dispose tests assert it stops growing).
class _FakeClient extends ShedClient {
  _FakeClient(this._streams) : super(_NoHttp(), _Tok());
  final List<Stream<RcEvent>> _streams;
  int connects = 0;

  @override
  Stream<RcEvent> rcEvents() {
    final i = connects++;
    return i < _streams.length ? _streams[i] : const Stream<RcEvent>.empty();
  }
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('activity.changed patches exactly one row in the overlay', () async {
    final s1 = StreamController<RcEvent>();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        shedClientProvider.overrideWith(
          (ref, name) async => _FakeClient([s1.stream]),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      s1.close();
    });
    container.listen(liveActivityProvider('h'), (_, _) {});
    // Let the stream provider resolve the client + subscribe.
    await container.read(liveActivityProvider('h').future);

    s1.add(
      const RcActivityChanged(
        shed: 'proj',
        slug: 'a',
        activity: RcActivity.working,
        state: RcState.ready,
      ),
    );
    await _tick();

    final overlay = container.read(liveActivityProvider('h')).value!;
    expect(overlay.lookup('proj', 'a')!.activity, RcActivity.working);
    // A row that never got an event stays absent (falls back to base snapshot).
    expect(overlay.lookup('proj', 'other'), isNull);
  });

  test('a reconnect that delivers data triggers exactly one overview refetch '
      '(and none on the first-ever connection)', () async {
    final s1 = StreamController<RcEvent>();
    final s2 = StreamController<RcEvent>();
    var overviewBuilds = 0;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        shedClientProvider.overrideWith(
          (ref, name) async => _FakeClient([s1.stream, s2.stream]),
        ),
        overviewProvider.overrideWith((ref, name) async {
          overviewBuilds++;
          return const OverviewUnsupported();
        }),
      ],
    );
    addTearDown(() {
      container.dispose();
      s1.close();
      s2.close();
    });
    container.listen(liveActivityProvider('h'), (_, _) {});
    container.listen(overviewProvider('h'), (_, _) {});
    await container.read(overviewProvider('h').future);
    await container.read(liveActivityProvider('h').future);
    expect(overviewBuilds, 1); // initial

    // First-ever connection delivers data → NO refetch (the view already holds
    // a fresh overview).
    s1.add(
      const RcActivityChanged(
        shed: 'proj',
        slug: 'a',
        activity: RcActivity.working,
      ),
    );
    s1.add(
      const RcActivityChanged(
        shed: 'proj',
        slug: 'stale',
        activity: RcActivity.working,
      ),
    );
    await _tick();
    expect(overviewBuilds, 1);

    // Drop the connection; the provider backs off (500ms) then reconnects.
    await s1.close();
    await Future<void>.delayed(const Duration(milliseconds: 650));

    // The reconnected stream's first frame triggers one overview refetch, and
    // the overlay is CLEARED first — a pre-drop patch ('stale') must not
    // survive to override the freshly-refetched snapshot.
    s2.add(
      const RcActivityChanged(
        shed: 'proj',
        slug: 'a',
        activity: RcActivity.idle,
      ),
    );
    await _tick();
    expect(overviewBuilds, 2);
    final overlay = container.read(liveActivityProvider('h')).value!;
    expect(overlay.lookup('proj', 'a')!.activity, RcActivity.idle);
    expect(overlay.lookup('proj', 'stale'), isNull); // cleared on reconnect
  });

  test('an event for a slug UNKNOWN to the overview triggers one debounced '
      'overview refetch; known-slug events trigger none', () async {
    final s1 = StreamController<RcEvent>();
    var overviewBuilds = 0;
    // A snapshot holding exactly one session: proj/known.
    final snapshot = Overview.fromJson({
      'server': {
        'version': '0.9.0',
        'features': ['overview', 'rc-events'],
      },
      'sheds': [
        {
          'name': 'proj',
          'status': 'running',
          'sessions': [
            {
              'name': 'rc-known',
              'rc': {'kind': 'codex', 'state': 'ready', 'managed': true},
            },
          ],
        },
      ],
    });
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        shedClientProvider.overrideWith(
          (ref, name) async => _FakeClient([s1.stream]),
        ),
        overviewProvider.overrideWith((ref, name) async {
          overviewBuilds++;
          return OverviewData(snapshot);
        }),
      ],
    );
    addTearDown(() {
      container.dispose();
      s1.close();
    });
    container.listen(liveActivityProvider('h'), (_, _) {});
    container.listen(overviewProvider('h'), (_, _) {});
    await container.read(overviewProvider('h').future);
    await container.read(liveActivityProvider('h').future);
    expect(overviewBuilds, 1);

    // Events for the KNOWN slug: no refetch — the overlay patches its card.
    s1.add(
      const RcActivityChanged(
        shed: 'proj',
        slug: 'known',
        activity: RcActivity.working,
        state: RcState.ready,
      ),
    );
    s1.add(
      const RcSessionUpdated(shed: 'proj', slug: 'known', state: RcState.ready),
    );
    await _tick();
    expect(overviewBuilds, 1);

    // A CLI-created session the snapshot doesn't hold: exactly ONE refetch,
    // even across a burst of events for it (debounce).
    for (var i = 0; i < 3; i++) {
      s1.add(
        const RcSessionUpdated(
          shed: 'proj',
          slug: 'brandnew',
          state: RcState.ready,
        ),
      );
      s1.add(
        const RcActivityChanged(
          shed: 'proj',
          slug: 'brandnew',
          activity: RcActivity.working,
          state: RcState.ready,
        ),
      );
    }
    await _tick();
    expect(overviewBuilds, 2);

    // A kill event (removed) for an unknown slug must NOT refetch — there is
    // nothing to materialize.
    s1.add(const RcSessionUpdated(shed: 'proj', slug: 'gone9', removed: true));
    await _tick();
    expect(overviewBuilds, 2);
  });

  test('dispose during a quiet stream cancels the SSE subscription', () async {
    var cancelled = false;
    final quiet = StreamController<RcEvent>(onCancel: () => cancelled = true);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        shedClientProvider.overrideWith(
          (ref, name) async => _FakeClient([quiet.stream]),
        ),
      ],
    );
    container.listen(liveActivityProvider('h'), (_, _) {});
    await container.read(liveActivityProvider('h').future);
    await _tick(); // connect() has subscribed to the quiet stream

    // No events ever arrive; disposing must still tear the subscription down
    // (the old async* generator parked in `await moveNext` could not be
    // cancelled — the SSE stayed open forever).
    container.dispose();
    await _tick();
    expect(cancelled, isTrue);
    await quiet.close();
  });

  test('dispose during backoff stops the reconnect loop '
      '(no zombie reconnector)', () async {
    // Every connection ends immediately → the provider is always either
    // connecting or in backoff.
    final client = _FakeClient(const []);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [shedClientProvider.overrideWith((ref, name) async => client)],
    );
    container.listen(liveActivityProvider('h'), (_, _) {});
    await container.read(liveActivityProvider('h').future);
    await _tick(); // first connect done; a 500ms retry timer is pending
    final connectsAtDispose = client.connects;
    expect(connectsAtDispose, greaterThanOrEqualTo(1));

    container.dispose();
    // Wait well past the pending backoff: a zombie loop would reconnect.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(client.connects, connectsAtDispose);
  });
}
