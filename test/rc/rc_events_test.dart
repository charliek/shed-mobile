import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/sse_parser.dart';
import 'package:shed_mobile/rc/rc_events.dart';
import 'package:shed_mobile/rc/rc_models.dart';

RcEvent? _parse(String event, String data) =>
    parseRcEvent(SseRawEvent(event, data));

void main() {
  group('parseRcEvent', () {
    test('activity.changed → typed patch (activity + lifecycle state)', () {
      final ev = _parse(
        'activity.changed',
        '{"shed":"proj","slug":"cdx777","activity":"needs_input",'
            '"activity_at":"2026-06-19T18:54:12Z","state":"ready"}',
      );
      expect(ev, isA<RcActivityChanged>());
      final a = ev! as RcActivityChanged;
      expect(a.shed, 'proj');
      expect(a.slug, 'cdx777');
      expect(a.activity, RcActivity.needsInput);
      expect(a.activityAt, '2026-06-19T18:54:12Z');
      expect(a.state, RcState.ready);
      expect(a.lastMessage, isNull); // not carried on this frame
    });

    test('activity.changed decodes a payload-carried last_message '
        '(and the reducer lets it supersede the held one)', () {
      final ev =
          _parse(
                'activity.changed',
                '{"shed":"proj","slug":"cdx777","activity":"working",'
                    '"state":"ready","last_message":"Running tests."}',
              )!
              as RcActivityChanged;
      expect(ev.lastMessage, 'Running tests.');

      var o = ActivityOverlay.empty.apply(
        const RcActivityChanged(
          shed: 'proj',
          slug: 'cdx777',
          activity: RcActivity.working,
          state: RcState.ready,
          lastMessage: 'older preview',
        ),
      );
      o = o.apply(ev);
      expect(o.lookup('proj', 'cdx777')!.lastMessage, 'Running tests.');

      // A frame WITHOUT last_message keeps the held preview (no wipe).
      o = o.apply(
        const RcActivityChanged(
          shed: 'proj',
          slug: 'cdx777',
          activity: RcActivity.needsInput,
          state: RcState.ready,
        ),
      );
      expect(o.lookup('proj', 'cdx777')!.lastMessage, 'Running tests.');
    });

    test(
      'session.updated extracts activity/state/last_message from session',
      () {
        final ev = _parse(
          'session.updated',
          '{"shed":"proj","slug":"cdx777","session":'
              '{"state":"dead","activity":"idle","last_message":"bye"}}',
        );
        final u = ev! as RcSessionUpdated;
        expect(u.state, RcState.dead);
        expect(u.activity, RcActivity.idle);
        expect(u.lastMessage, 'bye');
      },
    );

    test('message.appended → seq (notification only)', () {
      final ev = _parse('message.appended', '{"shed":"p","slug":"s","seq":42}');
      expect((ev! as RcMessageAppended).seq, 42);
    });

    test('synthetic hub.unavailable / shed.stopped decode', () {
      expect(
        _parse('hub.unavailable', '{"shed":"p"}'),
        isA<RcHubUnavailable>(),
      );
      expect(_parse('shed.stopped', '{"shed":"p"}'), isA<RcShedStopped>());
    });

    test('drops unknown events, non-object data, and missing keys', () {
      expect(_parse('heartbeat', '{"shed":"p"}'), isNull);
      expect(_parse('activity.changed', 'not-json'), isNull);
      expect(_parse('activity.changed', '{"shed":"p"}'), isNull); // no slug
      expect(
        _parse('message.appended', '{"shed":"p","slug":"s"}'),
        isNull,
      ); // no seq
    });

    test('non-string field values are tolerated (nulled), never thrown', () {
      // Guest-controlled frames: a wrong-typed value must be dropped/nulled —
      // a throw here would kill the SSE stream and turn one malformed frame
      // into a perpetual reconnect storm.
      final ev = _parse(
        'activity.changed',
        '{"shed":"p","slug":"a","activity":42,"activity_at":[],"state":7}',
      );
      expect(ev, isA<RcActivityChanged>());
      final a = ev! as RcActivityChanged;
      expect(a.activity, isNull);
      expect(a.activityAt, isNull);
      expect(a.state, isNull);
    });

    test('session.updated with a null/absent session body signals removal', () {
      final ev =
          _parse('session.updated', '{"shed":"p","slug":"a","session":null}')!
              as RcSessionUpdated;
      expect(ev.removed, isTrue);
      final ev2 =
          _parse('session.updated', '{"shed":"p","slug":"a"}')!
              as RcSessionUpdated;
      expect(ev2.removed, isTrue);
    });

    test('session.updated last_message strips Unicode format chars '
        '(bidi override / zero-width)', () {
      final ev =
          _parse(
                'session.updated',
                // JSON \u escapes: RLO (U+202E) + zero-width space (U+200B).
                '{"shed":"p","slug":"a","session":'
                    r'{"state":"ready","last_message":"a\u202erev\u200bersed"}}',
              )!
              as RcSessionUpdated;
      expect(ev.lastMessage, 'areversed');
    });
  });

  group('ActivityOverlay.apply', () {
    RcSessionKey key(String shed, String slug) => (shed: shed, slug: slug);

    test('activity.changed patches exactly one row, leaving others', () {
      var o = ActivityOverlay.empty;
      o = o.apply(
        const RcActivityChanged(
          shed: 'p',
          slug: 'a',
          activity: RcActivity.working,
          state: RcState.ready,
        ),
      );
      o = o.apply(
        const RcActivityChanged(
          shed: 'p',
          slug: 'b',
          activity: RcActivity.idle,
          state: RcState.ready,
        ),
      );
      expect(o.lookup('p', 'a')!.activity, RcActivity.working);
      expect(o.lookup('p', 'b')!.activity, RcActivity.idle);

      final next = o.apply(
        const RcActivityChanged(
          shed: 'p',
          slug: 'a',
          activity: RcActivity.needsInput,
          state: RcState.ready,
        ),
      );
      // Only row a moved; b is untouched; a fresh overlay object is returned.
      expect(next.lookup('p', 'a')!.activity, RcActivity.needsInput);
      expect(next.lookup('p', 'b')!.activity, RcActivity.idle);
      expect(identical(next, o), isFalse);
    });

    test('message.appended bumps lastSeq without wiping activity', () {
      var o = ActivityOverlay.empty.apply(
        const RcActivityChanged(
          shed: 'p',
          slug: 'a',
          activity: RcActivity.working,
          state: RcState.ready,
        ),
      );
      o = o.apply(const RcMessageAppended(shed: 'p', slug: 'a', seq: 7));
      expect(o.lookup('p', 'a')!.lastSeq, 7);
      expect(o.lookup('p', 'a')!.activity, RcActivity.working); // preserved
    });

    test('hub.unavailable / shed.stopped drop that shed\'s patches only', () {
      var o = ActivityOverlay.empty
          .apply(
            const RcActivityChanged(
              shed: 'p',
              slug: 'a',
              activity: RcActivity.working,
            ),
          )
          .apply(
            const RcActivityChanged(
              shed: 'q',
              slug: 'b',
              activity: RcActivity.idle,
            ),
          );
      final afterHub = o.apply(const RcHubUnavailable('p'));
      expect(
        afterHub.lookup('p', 'a'),
        isNull,
      ); // degraded → falls back to base
      expect(afterHub.lookup('q', 'b'), isNotNull);

      final afterStop = afterHub.apply(const RcShedStopped('q'));
      expect(afterStop.patches, isEmpty);
      // Dropping a shed with no patches returns the same overlay unchanged.
      expect(
        identical(afterStop.apply(const RcHubUnavailable('p')), afterStop),
        isTrue,
      );
    });

    test('lookup keys by (shed, slug)', () {
      final o = ActivityOverlay.empty.apply(
        const RcActivityChanged(
          shed: 'p',
          slug: 'a',
          activity: RcActivity.working,
        ),
      );
      expect(o.patches.containsKey(key('p', 'a')), isTrue);
      expect(o.lookup('p', 'z'), isNull);
    });

    test('session.updated removal drops the (shed, slug) patch entirely', () {
      var o = ActivityOverlay.empty
          .apply(
            const RcActivityChanged(
              shed: 'p',
              slug: 'a',
              activity: RcActivity.working,
              state: RcState.ready,
            ),
          )
          .apply(
            const RcActivityChanged(
              shed: 'p',
              slug: 'b',
              activity: RcActivity.idle,
            ),
          );
      // A kill (session:null) must REMOVE the patch — retaining the previous
      // fields would keep a dead session's live badge alive forever.
      o = o.apply(const RcSessionUpdated(shed: 'p', slug: 'a', removed: true));
      expect(o.lookup('p', 'a'), isNull);
      expect(o.lookup('p', 'b'), isNotNull); // others untouched
    });

    test('a blocking state suppresses activity AND last_message in the patch '
        '(whole-dimension suppression, mirroring the Go server)', () {
      var o = ActivityOverlay.empty.apply(
        const RcSessionUpdated(
          shed: 'p',
          slug: 'a',
          activity: RcActivity.working,
          state: RcState.ready,
          lastMessage: 'pre-death context',
        ),
      );
      o = o.apply(const RcMessageAppended(shed: 'p', slug: 'a', seq: 5));
      // The session dies: the patch keeps the state (and lastSeq) but must
      // clear activity and lastMessage — stale context is not current context.
      o = o.apply(
        const RcActivityChanged(
          shed: 'p',
          slug: 'a',
          activity: RcActivity.working,
          state: RcState.dead,
        ),
      );
      final p = o.lookup('p', 'a')!;
      expect(p.state, RcState.dead);
      expect(p.activity, isNull);
      expect(p.lastMessage, isNull);
      expect(p.lastSeq, 5); // retained — the feed history stays readable
    });
  });
}
