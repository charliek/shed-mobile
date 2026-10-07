// **The phone's craze source, against the REAL hub** (plan 025 §3.7.2,
// §3.7.4; shed-mobile#34).
//
// Every craze process here is one of shed's pinned binaries, run under craze's
// own hermetic recipe (`support/craze_rig.dart`): the real hub — born by the
// first bridge — over a `craze-fake-host` registry entry, its creates spawning
// `craze-fake-agent` as grok. The reach is the feed's own tunnel seam
// (`machineTunnelOpenProvider` / `MachineFeed.openTunnel`) with its SSH exec
// replaced by a local `/bin/sh` running the JAILED ladder, so every cell drives
// the REAL feed, the REAL source handle over FRB, and the REAL row merge — and
// nothing installed on this host can answer.
//
// Without `SHED_CRAZE_BIN_DIR` the hub cells SKIP; `SHED_CRAZE_REQUIRE=1` (CI)
// turns that into a failure, so the job can never go green on skipped cells.
//
// ## The cells (CM3: the source)
//
// * **rows** — a fake host's row and a created session's, through the provider
//   graph and onto the screen, with the hub's own facts (needs-you, the head
//   ask, the provider, the workspace); a created row is listed at once.
// * **the fold** — a craze-owned roost tab collapses into the hub row it names
//   (one row per session), a tab of another source with the same id does not,
//   an unmatched craze tab is hidden; with the feed down roost's rows stand
//   alone again beside the hub row's last-known copy. And the C9 cases — the
//   tie-breaks, the hidden-unmatched, the other-source, the dormant — against
//   the FRB call itself.
// * **not installed / too old** — the jailed ladder with no craze on its PATH,
//   and the REAL craze v0.0.1: Dart's pre-`hello` classifier names each (Rust,
//   over a loopback port, could only say `Unreachable`); not installed is
//   quiet, too old says so.
// * **restart** — an open craze transcript leaves a retired source at once and
//   comes back live through its replacement (a send lands after); no lane is
//   ever opened through a source that has not seeded; a craze half that
//   failed to start (its port, then its source) is retried by the next start
//   alone, roost left running, its source a new epoch; and a stop + start
//   landing while a start or a craze retry is in flight ends with the feed
//   started at the new generation, one watcher — unless the stop came after
//   the start was asked for.
// * **teardown** — the feed disposed while its craze source is opening, a live
//   feed disposed, and one disposed while its roost watcher is quiet: every
//   bridge counter back to zero, the craze tunnel's port closed, and no wait on
//   roost's next frame. And a restart closes the old source handle before the
//   next one opens on the new port.
//
// ## The cells (CM4: create, §3.8)
//
// The create screen's craze choice, driven as a person would, against craze's
// OWN createOptions and creates — the desktop's C10 cells:
//
// * **the sheet** — craze's providers in craze's order, cursor (no
//   `cursor-agent` on the rig's PATH) and native (no key) dimmed with craze's
//   reason and fix and refusing a tap, grok (craze's default) preselected; the
//   recent directories craze sends; a first prompt craze takes; and the
//   created session's transcript open AT ONCE in place of the screen, its
//   prompt echoed.
// * **folded at once** — with the source's nudges held back, the created row
//   is in the feed's state the moment the create returns: what lets the
//   transcript open before the roster (or any nudge) has caught up.
// * **an unknown outcome** — the bridge carrying the create is cut once the hub
//   has it (and so is shed-craze's own retry, under the same id): the screen
//   says the outcome is unknown and HOLDS the id; Try again resumes it, and
//   exactly one session results.
// * **a start failure** — grok's agent dies at its start: craze's cause,
//   verbatim, the form kept, no id held; with the config fixed, Try again
//   sends a NEW id and one session results.
//
// ## The cells (CM5: the transcript, §3.7.3)
//
// The transcript screen, driven as a person would, against craze's own lane —
// the desktop's C9 lane cells, plus the phone's own resume:
//
// * **seed, send, stop** — a created session's transcript seeds (its first
//   prompt echoed), its header reads the LIVE session row ("runs tools without
//   asking": a create runs `bypass`), a send is echoed; Stop asks first, ends
//   the SESSION (`session_closed`), the transcript stays, the lane is never
//   re-opened, and the row leaves.
// * **answers** — a permission, a question and a plan raised by the fake host
//   are cards, answered on screen by the offered ids.
// * **cancel** — offered only while a turn runs (the fake host holds one open,
//   `hang_next`), and it ends the turn.
// * **the silent resume** — the LANE's own connection process killed (not the
//   feed tunnel's listener, not the roster's) and its redial held for a few
//   seconds: the same lane handle, no reseed (no full read, the generation
//   unchanged), "reconnecting…" shown and then cleared, then a send that lands.
// * **the ghost row** (Amendment A16) — with the roster's own bridge FROZEN, so
//   no roster frame can list or remove it, a session created and stopped at
//   once leaves the rows: the source's `on_created_gone`, through the feed.
//
// ## The cells (CM6: settings, §3.10)
//
// The transcript's settings chip and sheet against craze's permodel cursor
// (`craze-fake-agent -script permodel`, four models each with an option
// catalog of its own) — the desktop's C11 cells:
//
// * **the sheet, and a model change** — the chip reads the CURRENT values;
//   the sheet lists the model, grok-4.6's options and the mode; with the
//   agent holding its answer the model row is PENDING with no optimistic
//   value, and once it answers the sheet redraws claude-opus-5's OWN options
//   from the session's next `Settings`. An option change goes out bound to
//   the model the sheet shows (A13).
// * **a refusal, inline** — a second client moves the model while the agent
//   holds that change; the sheet's effort press, chosen on the model it
//   showed, is refused `stale_model` on its own row ("the model changed; try
//   again") and never reaches the agent; the retry is a NEW command.
// * **the model the sheet DISPLAYED** (A13) — the lane folds another client's
//   move while the screen, held, still shows the old model: an option pressed
//   there goes out bound to the model shown and is refused `stale_model`,
//   never applied to the model the session moved to.
// * **another client's change** — appears in the open sheet, nothing pressed.
// * **a change lost to a drop** — the lane's own bridge cut once craze has the
//   change (and its redial held): the row says "not confirmed", still showing
//   the old value; when the lane resumes, its next `Settings` replaces the
//   mark with the real value; the change ran once and was never resent.
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/features/craze/craze_create.dart';
import 'package:shed_mobile/features/craze/craze_create_sheet.dart';
import 'package:shed_mobile/features/create/create_rc_target.dart';
import 'package:shed_mobile/features/lanes/lane_screen.dart';
import 'package:shed_mobile/features/machines/machine_sessions_view.dart';
import 'package:shed_mobile/features/rc/create_rc_screen.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_settings.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/lanes/lane_state.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/bridge_rt.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/roost_entitlement.dart';
import 'package:shed_mobile/ssh/roost_tunnel.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import 'support/craze_rig.dart';

/// The machine every cell's feed is for. Its host is never dialled: the
/// tunnel seam runs a local process instead.
const _local = MachineRecord(name: 'local', host: '127.0.0.1');

/// The fake host's registry identity (twelve hex digits, as craze mints them).
const _fake = '0c0c0c0c0c0c';
const _fakeSession = 'craze-mob-fake';

/// Every cell gets ninety seconds: a hub's birth, a create (the fake agent
/// answers at once) and a slow retry fit with room; a hung cell is a failure,
/// not a hung CI job.
const _cell = Timeout(Duration(seconds: 90));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  final bins = CrazeBins.resolve();
  final skip = bins == null;
  if (skip) {
    // ignore: avoid_print
    print('skipping the craze hub cells: ${CrazeBins.why}');
  }

  // -------------------------------------------------------------------------
  // rows
  // -------------------------------------------------------------------------

  testWidgets(
    'rows_from_a_fake_host_and_a_created_session',
    (tester) async {
      final rig = await _rig(bins!);
      await rig.fakeHost(_fake, _fakeSession);

      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          machinesProvider.overrideWith((ref) async => const [_local]),
          identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
          // THE seam: the feed's own tunnels, the SSH exec a local process.
          machineTunnelOpenProvider.overrideWithValue(rig.tunnelOpen),
        ],
      );
      addTearDown(() => _dispose(tester, container));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: shedLightTheme,
            home: const Scaffold(
              body: SingleChildScrollView(child: MachineSessionsView()),
            ),
          ),
        ),
      );
      // A LISTENER, not a read: the feed is `autoDispose`, and a bare read of
      // it would build a feed, drop it, and tear it down under its own start.
      final feedState = container.listen(
        machineFeedProvider(_local.name),
        (_, _) {},
        fireImmediately: true,
      );
      MachineFeedState? state() => feedState.read().value;

      await _until(
        tester,
        () => (state()?.craze?.live ?? false) && _row(state(), _fake) != null,
        what: 'the fake host\'s craze row',
      );
      final fake = _row(state(), _fake)!;
      expect(fake.stale, isFalse);
      expect(
        fake.session.id,
        _fake,
        reason: 'a row\'s key is its hostId (P11)',
      );
      expect(state()!.craze!.caps?.create, isTrue);

      // needs-you, with the head ask's summary — the hub's own facts.
      rig.op({
        'name': 'permission',
        'id': 'perm-1',
        'tool': 'Shell',
        'options': [
          {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
        ],
      });
      await _until(
        tester,
        () => _row(state(), _fake)?.session.pendingApprovals == 1,
        what: 'the ask on the row',
      );
      final asked = _row(state(), _fake)!.session;
      expect(asked.activity, BridgeRcActivity.needsApproval);
      expect(asked.headAskSummary, 'permission Shell');
      expect(
        find.text('needs you (1): permission Shell'),
        findsOneWidget,
        reason: 'the machine group renders the hub row',
      );

      // A create through the feed's own source: its row is listed AT ONCE,
      // before any roster flush (the source's created rows).
      final feed = container.read(machineFeedControllerProvider(_local.name));
      final created = await feed.crazeCreateSession(
        BridgeLaneCreateRequest(
          cwd: rig.work,
          prompt: 'hello phone',
          requestId: crazeNewRequestId(),
        ),
      );
      expect(created.prompt, const BridgeLanePromptOutcome.accepted());
      final host = created.session.id;
      await _until(
        tester,
        () => _row(state(), host) != null,
        what: 'the created session\'s row',
      );
      final row = _row(state(), host)!;
      expect(row.session.provider, 'grok');
      expect(row.session.cwd, rig.work);
      expect(row.stale, isFalse);
      expect(
        state()!.rows.whereType<RoostMachineRow>(),
        isEmpty,
        reason: 'no roost here: a machine with craze and no roost still lists',
      );

      final c = await liveCounters();
      expect(c.activeCrazeSources, BigInt.one, reason: 'one source per feed');
      expect(c.activeCrazeForwarders, BigInt.one);
    },
    skip: skip,
    timeout: _cell,
  );

  // -------------------------------------------------------------------------
  // the fold
  // -------------------------------------------------------------------------

  testWidgets(
    'a_craze_tab_is_one_row_and_roost_returns_when_the_feed_drops',
    (tester) async {
      final rig = await _rig(bins!);
      await rig.fakeHost(_fake, _fakeSession);
      final feed = _feed(rig);
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();

      await _until(
        tester,
        () =>
            (feed.state.craze?.live ?? false) &&
            _row(feed.state, _fake) != null,
        what: 'the fake host\'s craze row',
      );
      final psid = _row(feed.state, _fake)!.session.providerSessionId;
      expect(
        psid,
        isNotNull,
        reason: 'the hub row names the provider session a TUI tab claims',
      );

      // A roost snapshot with the session's TUI tab (owned `(craze, psid)`),
      // an opencode tab whose session id happens to be the same, and a craze
      // tab the roster names no row for.
      feed.applyRoostUpdateForTest(
        BridgeRoostUpdate.snapshot(
          sessions: [
            _tab(7, const BridgeRcKind.craze(), rcId: psid),
            _tab(8, const BridgeRcKind.opencode(), rcId: psid),
            _tab(9, const BridgeRcKind.craze(), rcId: 'ses-nobody'),
          ],
        ),
      );
      final rows = feed.state.rows;
      expect(
        rows.whereType<RoostMachineRow>().map((r) => r.session.tabId),
        [8],
        reason:
            'tab 7 is the hub row; tab 9 (unmatched) is hidden; only '
            'craze ownership folds, so the opencode tab stands',
      );
      expect(
        rows.where((r) => r.key == _fake || r.key == '7'),
        hasLength(1),
        reason: 'ONE row per craze session',
      );
      expect(_row(feed.state, _fake)!.tabId, 7, reason: 'carrying its tab');

      // The feed goes down for good: no craze to redial, and the hub stopped.
      rig.uninstall();
      await rig.sigtermHub();
      await _until(
        tester,
        () => !(feed.state.craze?.live ?? true),
        what: 'the craze feed to drop',
      );
      final down = feed.state.rows;
      expect(
        down.whereType<RoostMachineRow>().map((r) => r.session.tabId),
        [7, 8, 9],
        reason:
            'with the hub feed down, nothing is absorbed: roost stands alone',
      );
      final retained = _row(feed.state, _fake)!;
      expect(retained.stale, isTrue, reason: 'the last known row, stale');
      expect(retained.tabId, isNull);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets('the_fold_cases_against_the_frb_call', (_) async {
    // The C9 cases, duplicated against the bridge: the rule is shed's
    // (`shed_app::craze_rows::fold_plan`), and this proves the call the feed
    // makes carries it whole.
    BridgeLaneSession hub(String id, String psid, int? since) =>
        BridgeLaneSession(
          id: id,
          title: id,
          cwd: '/w',
          activity: BridgeRcActivity.idle,
          pendingApprovals: 0,
          approximate: false,
          lastChangeUnixMs: since,
          sinceUnixMs: since,
          providerSessionId: psid,
        );
    BridgeRoostTabRef craze(int tab, String owner) =>
        BridgeRoostTabRef(tabId: tab, crazeOwner: owner);
    Map<int, String?> folded(BridgeFoldPlan plan) => {
      for (final t in plan.folded) t.tabId: t.hostId,
    };

    // Dormant (the feed is not live): nothing is absorbed.
    expect(crazeFoldPlan(roost: [craze(4, 'ses-a')]).folded, isEmpty);
    // Attached to the row it names; a plain tab is never folded.
    expect(
      folded(
        crazeFoldPlan(
          roost: [craze(4, 'ses-a'), const BridgeRoostTabRef(tabId: 5)],
          hub: [hub('aaaaaaaaaaaa', 'ses-a', 10)],
        ),
      ),
      {4: 'aaaaaaaaaaaa'},
    );
    // The other source: an opencode tab whose id equals the session's is NOT
    // craze's.
    expect(
      crazeFoldPlan(
        roost: [const BridgeRoostTabRef(tabId: 7)],
        hub: [hub('aaaaaaaaaaaa', 'ses-a', 10)],
      ).folded,
      isEmpty,
    );
    // Hidden-unmatched: live is live, even with an empty roster.
    expect(folded(crazeFoldPlan(roost: [craze(4, 'ses-unknown')], hub: [])), {
      4: null,
    });
    // Two tabs of one session: the newest attaches, the rest fold silently.
    expect(
      folded(
        crazeFoldPlan(
          roost: [craze(3, 'ses-a'), craze(9, 'ses-a'), craze(6, 'ses-a')],
          hub: [hub('aaaaaaaaaaaa', 'ses-a', 10)],
        ),
      ),
      {3: null, 6: null, 9: 'aaaaaaaaaaaa'},
    );
    // Two rows claiming one session: the newer, whatever the order …
    for (final rows in [
      [hub('ffffffffffff', 'ses-a', 10), hub('111111111111', 'ses-a', 20)],
      [hub('111111111111', 'ses-a', 20), hub('ffffffffffff', 'ses-a', 10)],
    ]) {
      expect(folded(crazeFoldPlan(roost: [craze(4, 'ses-a')], hub: rows)), {
        4: '111111111111',
      });
    }
    // … a time beats none …
    expect(
      folded(
        crazeFoldPlan(
          roost: [craze(4, 'ses-a')],
          hub: [
            hub('ffffffffffff', 'ses-a', null),
            hub('111111111111', 'ses-a', 20),
          ],
        ),
      ),
      {4: '111111111111'},
    );
    // … and a tie goes to the greater hostId.
    expect(
      folded(
        crazeFoldPlan(
          roost: [craze(4, 'ses-a')],
          hub: [
            hub('aaaaaaaaaaaa', 'ses-a', 10),
            hub('bbbbbbbbbbbb', 'ses-a', 10),
          ],
        ),
      ),
      {4: 'bbbbbbbbbbbb'},
    );
  });

  // -------------------------------------------------------------------------
  // not installed / too old
  // -------------------------------------------------------------------------

  testWidgets(
    'not_installed_is_quiet',
    (tester) async {
      final rig = await _rig(bins!, path: CrazePath.empty);
      // A craze at an ABSOLUTE rung the production ladder would reach and the
      // jailed one never may: it must never run.
      final sentinel = File('${rig.home}/.nix-profile/bin/craze');
      final ran = '${rig.root}/sentinel-ran';
      sentinel.parent.createSync(recursive: true);
      sentinel.writeAsStringSync('#!/bin/sh\ntouch \'$ran\'\nexit 2\n');
      await Process.run('chmod', ['0755', sentinel.path]);

      final feed = _feed(rig);
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();
      await _until(
        tester,
        () =>
            feed.state.craze?.offline?.cause
                is BridgeSourceOffline_NotInstalled,
        what: 'craze read as NOT INSTALLED',
      );
      expect(
        feed.state.craze!.offline!.reason,
        'craze: command not found',
        reason: 'the ladder\'s own line, as the band carried it',
      );
      expect(feed.state.rows, isEmpty);
      expect(
        crazeNoteFor(feed.state),
        isNull,
        reason: 'not installed is quiet',
      );
      expect(File(ran).existsSync(), isFalse, reason: 'a host craze answered');
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'too_old_says_so_with_the_real_v0_0_1',
    (tester) async {
      final rig = await _rig(bins!, path: CrazePath.tooOld);
      final feed = _feed(rig);
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();
      await _until(
        tester,
        () => feed.state.craze?.offline?.cause is BridgeSourceOffline_TooOld,
        what: 'craze v0.0.1 read as TOO OLD',
      );
      expect(
        feed.state.craze!.offline!.reason,
        contains('unknown flag: --hub'),
      );
      expect(feed.state.rows, isEmpty);
      expect(
        crazeNoteFor(feed.state),
        'craze on this machine is too old for shed; update it',
      );
    },
    skip: skip,
    timeout: _cell,
  );

  // -------------------------------------------------------------------------
  // teardown
  // -------------------------------------------------------------------------

  testWidgets(
    'teardown_during_a_source_open_returns_every_counter',
    (tester) async {
      final rig = await _rig(bins!);

      // The feed disposed WHILE its craze source is being opened: the open
      // completes after the stop, and the handle it hands back must be closed
      // rather than installed behind the feed's back.
      final reached = Completer<void>();
      final release = Completer<void>();
      Future<BridgeCrazeSource> held({
        required String machine,
        required int port,
      }) async {
        reached.complete();
        await release.future;
        return crazeSourceOpen(machine: machine, port: port);
      }

      final feed = _feed(rig, openCrazeSource: held);
      // A backstop only: the cell disposes it itself, mid-open.
      addTearDown(() => feed.dispose());
      final starting = feed.start();
      await _until(tester, () => reached.isCompleted, what: 'the source open');
      final port = feed.crazeTunnelPort;
      expect(port, isNotNull, reason: 'the craze tunnel is up by then');
      final disposing = feed.dispose();
      release.complete();
      await starting.timeout(const Duration(seconds: 20));
      await disposing.timeout(const Duration(seconds: 20));
      await _zero(tester, what: 'a feed disposed mid-open');
      await _refused(port!);

      // And a LIVE feed: tunnel, source, nudge stream and roster connection.
      final live = _feed(rig);
      addTearDown(() => live.dispose());
      await live.start();
      await _until(
        tester,
        () => live.state.craze?.live ?? false,
        what: 'the craze feed live',
      );
      final c = await liveCounters();
      expect(c.activeCrazeSources, BigInt.one);
      expect(c.activeCrazeForwarders, BigInt.one);
      final livePort = live.crazeTunnelPort!;
      await live.dispose().timeout(const Duration(seconds: 20));
      await _zero(tester, what: 'a live feed disposed');
      await _refused(livePort);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_quiet_roost_does_not_hold_the_teardown',
    (tester) async {
      // The roost watcher redials on a doubling backoff (500 ms → 30 s) and
      // says `Down` once per refused attempt, so after its SIXTH it is quiet
      // for sixteen seconds. A teardown that awaited the roost stream's cancel
      // before stopping the watcher waited for that next `Down` — on a healthy
      // machine, for roost's next push — and the craze half, which is torn
      // down after it, stayed open the whole time.
      final rig = await _rig(bins!);
      final feed = _feed(rig);
      addTearDown(() => feed.dispose());
      await feed.start();
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the craze feed live',
      );
      await _until(
        tester,
        () => rig.roostDials >= 6,
        what: 'the roost watcher\'s sixth refused dial',
      );
      final port = feed.crazeTunnelPort!;
      await feed.dispose().timeout(const Duration(seconds: 5));
      await _zero(tester, what: 'a feed disposed behind a quiet roost');
      await _refused(port);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'an_open_craze_lane_moves_to_the_replacement_source',
    (tester) async {
      // A feed restart (a roost bootstrap completing does one) closes the
      // craze tunnel and the source an open transcript rides, and opens new
      // ones on a new port. The lane must leave the old port and come back
      // live through the new source at once — not redial a closed port until
      // shed-craze's outage bound ends it, minutes later.
      final rig = await _rig(bins!);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          machinesProvider.overrideWith((ref) async => const [_local]),
          identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
          machineTunnelOpenProvider.overrideWithValue(rig.tunnelOpen),
        ],
      );
      addTearDown(() => _dispose(tester, container));
      final feedState = container.listen(
        machineFeedProvider(_local.name),
        (_, _) {},
        fireImmediately: true,
      );
      await _until(
        tester,
        () => feedState.read().value?.craze?.live ?? false,
        what: 'the craze feed live',
      );
      final feed = container.read(machineFeedControllerProvider(_local.name));
      final created = await feed.crazeCreateSession(
        BridgeLaneCreateRequest(
          cwd: rig.work,
          prompt: 'before the restart',
          requestId: crazeNewRequestId(),
        ),
      );
      final host = created.session.id;

      // The transcript, open through the provider graph the screen uses.
      final ref = (machine: _local.name, kind: crazeLaneKind, slug: host);
      container.listen(
        laneStateProvider(ref),
        (_, _) {},
        fireImmediately: true,
      );
      LaneController lane() => container.read(laneControllerProvider(ref));
      bool shows(String text) =>
          lane().state.rows.any((r) => r.text?.contains(text) ?? false);
      await _until(
        tester,
        () => lane().isOpen && shows('echo: before the restart'),
        what: 'the transcript seeded through the first source',
      );
      final controller = lane();
      final oldPort = feed.crazeTunnelPort!;
      final oldEpoch = feed.crazeLiveEpoch;
      final oldBridges = List.of(rig.bridges);

      await feed.stop();
      // Stopped: the lane on the retired source is CLOSED, and waits — it does
      // not sit redialling the closed port, and it is not given up on.
      await _until(
        tester,
        () => !controller.isOpen && controller.state.retrying,
        what: 'the lane to leave its retired source',
      );
      expect(controller.state.abandoned, isFalse);
      expect((await liveCounters()).activeLanes, BigInt.zero);

      await feed.start();
      await _until(
        tester,
        () => feed.crazeLiveEpoch != null && feed.crazeLiveEpoch != oldEpoch,
        what: 'the replacement source live',
      );
      await _until(
        tester,
        () =>
            controller.isOpen &&
            controller.state.stale == null &&
            !controller.state.retrying &&
            shows('echo: before the restart'),
        what: 'the transcript live again through the replacement source',
      );
      expect(
        lane(),
        same(controller),
        reason: 'the same transcript — one controller across the restart',
      );
      expect(controller.state.abandoned, isFalse);
      await _refused(oldPort);
      for (final bridge in oldBridges) {
        await bridge.exitCode.timeout(const Duration(seconds: 10));
      }

      // And it is live: a send lands, through the new tunnel.
      await controller.send('after the restart');
      await _until(
        tester,
        () => shows('echo: after the restart'),
        what: 'the send after the restart to land',
      );
      expect(controller.state.composerError, isNull);
      expect(
        (await liveCounters()).activeLanes,
        BigInt.one,
        reason: 'the lane on the retired source was closed, not leaked',
      );
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_lane_is_never_opened_through_an_unseeded_source',
    (tester) async {
      // A restart's replacement source lists no row until its roster seeds; a
      // lane bound through it then would read its own session as UNKNOWN —
      // permanent. So until the seed the feed refuses, and that refusal is
      // transient (the lane's ladder, or the source's live signal, opens it).
      final rig = await _rig(bins!);
      await rig.fakeHost(_fake, _fakeSession);
      rig.holdCrazeDials = Completer<void>();
      final feed = _feed(rig);
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();
      expect(feed.crazeLiveEpoch, isNull, reason: 'installed, not seeded');
      await expectLater(
        feed.openCrazeLane(_fake),
        throwsA(isA<StateError>()),
        reason: 'refused while unseeded — not bound into an unknown session',
      );

      rig.holdCrazeDials!.complete();
      rig.holdCrazeDials = null;
      await _until(
        tester,
        () => feed.crazeLiveEpoch != null && _row(feed.state, _fake) != null,
        what: 'the source seeded',
      );
      final lane = await feed.openCrazeLane(_fake);
      laneClose(lane: lane);
      lane.dispose();
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_restart_closes_the_old_source_before_opening_the_next',
    (tester) async {
      final rig = await _rig(bins!);
      final feed = _feed(rig);
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the craze feed live',
      );
      final before = feed.crazeTunnelPort;

      await feed.stop();
      expect(
        (await liveCounters()).activeCrazeSources,
        BigInt.zero,
        reason: 'the stop closed the source with the tunnel',
      );
      expect(
        feed.state.craze?.live,
        isFalse,
        reason: 'a stopped feed keeps its craze rows, last known',
      );

      await feed.start();
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the craze feed live again, on the new tunnel',
      );
      expect(feed.crazeTunnelPort, isNot(before), reason: 'a new port');
      final c = await liveCounters();
      expect(c.activeCrazeSources, BigInt.one, reason: 'ONE handle, never two');
      expect(c.activeCrazeForwarders, BigInt.one);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_failed_craze_start_is_retried_by_the_next_start_and_roost_is_left_alone',
    (tester) async {
      // craze's half failing at start — its tunnel not binding, then its
      // source not opening — leaves roost running and craze absent. The NEXT
      // start retries the craze half alone: roost's tunnel and watcher stay
      // the first start's, and the source it brings up is a new epoch,
      // announced as any replacement source is (CodeRabbit, shed-mobile#36).
      final rig = await _rig(bins!);
      var roostTunnels = 0;
      var crazeTunnels = 0;
      Future<RoostTunnel> tunnels({
        required Future<SSHClient> Function() connect,
        required String remoteCommand,
        required String machine,
        void Function(String)? onStderr,
      }) async {
        if (remoteCommand != crazeRemoteCommand()) {
          roostTunnels++;
        } else if (++crazeTunnels == 1) {
          throw const SocketException('the craze port would not bind');
        }
        return rig.tunnelOpen(
          connect: connect,
          remoteCommand: remoteCommand,
          machine: machine,
          onStderr: onStderr,
        );
      }

      var sourceOpens = 0;
      Future<BridgeCrazeSource> sources({
        required String machine,
        required int port,
      }) async {
        if (++sourceOpens == 1) {
          throw StateError('the craze source would not open');
        }
        return crazeSourceOpen(machine: machine, port: port);
      }

      final feed = _feed(rig, openTunnel: tunnels, openCrazeSource: sources);
      addTearDown(() => _disposeFeed(tester, feed));
      final announced = <int?>[];
      final sub = feed.crazeSources.listen(announced.add);
      addTearDown(sub.cancel);

      // The craze port will not bind: roost runs, craze is absent.
      await feed.start();
      final roostPort = feed.tunnelPort;
      expect(feed.isRunning, isTrue, reason: 'roost runs without craze');
      expect(roostPort, isNotNull);
      expect((roostTunnels, crazeTunnels, sourceOpens), (1, 1, 0));
      expect(feed.crazeTunnelPort, isNull);
      expect(feed.crazeLiveEpoch, isNull);

      // The next start retries craze alone; its source will not open, and
      // the tunnel that attempt bound goes with it.
      await feed.start();
      expect(
        (roostTunnels, crazeTunnels, sourceOpens),
        (1, 2, 1),
        reason: 'the craze half retried, roost left alone',
      );
      expect(feed.crazeTunnelPort, isNull);
      expect((await liveCounters()).activeCrazeSources, BigInt.zero);

      // And the next brings craze up.
      await feed.start();
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the craze feed live after the retry',
      );
      expect(
        (roostTunnels, crazeTunnels, sourceOpens),
        (1, 3, 2),
        reason: 'roost was never restarted for craze',
      );
      expect(feed.tunnelPort, roostPort);
      expect(feed.isRunning, isTrue);
      final epoch = feed.crazeLiveEpoch;
      expect(epoch, isNotNull);
      expect(announced, [epoch], reason: 'announced: a new epoch');
      final c = await liveCounters();
      expect(c.activeWatchers, BigInt.one, reason: 'one roost watcher, still');
      expect(c.activeCrazeSources, BigInt.one);
      expect(c.activeCrazeForwarders, BigInt.one);

      // Up: a further start changes nothing.
      await feed.start();
      expect((roostTunnels, crazeTunnels, sourceOpens), (1, 3, 2));
      expect(feed.crazeLiveEpoch, epoch);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_start_asked_for_while_a_start_runs_is_run_after_it',
    (tester) async {
      // A roost install completing restarts the feed — `stop()`, then
      // `start()` (`_entitle`). Landing while a start is still opening its
      // craze source, that start used to return early on the guard; the start
      // in flight, fenced off by the stop, built nothing more; and the feed
      // stayed stopped (Cursor's review of the CodeRabbit fix,
      // shed-mobile#36).
      final rig = await _rig(bins!);
      final gate = _HeldSources()..hold = Completer<void>();
      final feed = _feed(rig, openCrazeSource: gate.open);
      addTearDown(() => _disposeFeed(tester, feed));
      final first = feed.start();
      await _until(
        tester,
        () => gate.waiting,
        what: 'the first start opening its craze source',
      );
      final before = feed.tunnelPort;
      expect(before, isNotNull);

      await feed.stop();
      await feed.start(); // asked for while the first is still in flight
      gate.release();
      await first.timeout(const Duration(seconds: 20));
      expect(feed.isRunning, isTrue, reason: 'the start asked for ran');
      expect(
        feed.tunnelPort,
        allOf(isNotNull, isNot(before)),
        reason: 'a new roost tunnel: the new generation',
      );
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the restarted feed\'s craze live',
      );
      expect(gate.opens, 2);
      final c = await liveCounters();
      expect(c.activeWatchers, BigInt.one, reason: 'exactly one watcher');
      expect(c.activeCrazeSources, BigInt.one);
      expect(c.activeCrazeForwarders, BigInt.one);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_start_asked_for_while_a_craze_retry_runs_is_run_after_it',
    (tester) async {
      // The same restart landing while a start retries the craze half alone
      // (roost up, craze's first start failed): the retry is fenced off by
      // the stop, and the start asked for must still run.
      final rig = await _rig(bins!);
      final gate = _HeldSources()..failNext = true;
      final feed = _feed(rig, openCrazeSource: gate.open);
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();
      expect(feed.isRunning, isTrue);
      expect(feed.crazeTunnelPort, isNull, reason: 'craze\'s source failed');

      gate.hold = Completer<void>();
      final retry = feed.start(); // the craze half alone
      await _until(
        tester,
        () => gate.waiting,
        what: 'the craze retry opening its source',
      );
      final before = feed.tunnelPort;
      expect(before, isNotNull);

      await feed.stop();
      await feed.start(); // asked for while the retry is still in flight
      gate.release();
      await retry.timeout(const Duration(seconds: 20));
      expect(feed.isRunning, isTrue, reason: 'the start asked for ran');
      expect(
        feed.tunnelPort,
        allOf(isNotNull, isNot(before)),
        reason: 'a new roost tunnel: the new generation',
      );
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the restarted feed\'s craze live',
      );
      expect(gate.opens, 3);
      final c = await liveCounters();
      expect(c.activeWatchers, BigInt.one, reason: 'exactly one watcher');
      expect(c.activeCrazeSources, BigInt.one);
      expect(c.activeCrazeForwarders, BigInt.one);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_start_asked_for_and_then_stopped_does_not_run',
    (tester) async {
      // The request is not a restart of its own: an owner that stops the
      // feed AFTER asking for a start gets a stopped feed.
      final rig = await _rig(bins!);
      final gate = _HeldSources()..hold = Completer<void>();
      final feed = _feed(rig, openCrazeSource: gate.open);
      addTearDown(() => _disposeFeed(tester, feed));
      final first = feed.start();
      await _until(
        tester,
        () => gate.waiting,
        what: 'the first start opening its craze source',
      );

      await feed.start(); // asked for while the first is in flight…
      await feed.stop(); // …and then the feed is stopped
      gate.release();
      await first.timeout(const Duration(seconds: 20));
      expect(feed.isRunning, isFalse, reason: 'the stop outranks the request');
      expect(feed.tunnelPort, isNull);
      expect(gate.opens, 1);
      await _zero(tester, what: 'a feed stopped after a start was asked for');
    },
    skip: skip,
    timeout: _cell,
  );

  // -------------------------------------------------------------------------
  // create (CM4, §3.8)
  // -------------------------------------------------------------------------

  testWidgets(
    'the_sheet_renders_crazes_options_and_opens_the_transcript_at_once',
    (tester) async {
      final rig = await _rig(bins!);
      final screen = await _createScreen(tester, rig, show: false);
      final feed = screen.feed;

      // A session craze already ran in `work`: its directory is a recent one
      // once craze's session index has its row (written when the session is
      // established, a moment after the create answers). Before the screen
      // opens: the sheet reads its options when it opens, and only then.
      await feed.crazeCreateSession(
        BridgeLaneCreateRequest(
          cwd: rig.work,
          prompt: 'hello recent',
          requestId: crazeNewRequestId(),
        ),
      );
      final indexed = DateTime.now().add(const Duration(seconds: 30));
      while (!(await feed.crazeOptions()).recentDirs.contains(rig.work)) {
        if (DateTime.now().isAfter(indexed)) {
          fail('craze never listed ${rig.work} as a recent directory');
        }
        await tester.pump(const Duration(milliseconds: 300));
      }
      final sheet = _mkdir('${rig.root}/w-sheet');
      final before = rig.creates.length;

      await _showCreateScreen(tester, screen.container);
      await _chooseCraze(tester);
      // craze's providers, in craze's order.
      expect(_providerRows(), [
        'craze-provider-cursor',
        'craze-provider-grok',
        'craze-provider-native',
      ]);
      expect(_textAt('craze-provider-state-cursor'), 'unavailable');
      expect(
        _textAt('craze-provider-reason-cursor'),
        'cursor-agent not found on PATH',
      );
      expect(_textAt('craze-provider-fix-cursor'), contains('cursor-agent'));
      expect(_textAt('craze-provider-state-native'), 'needs setup');
      expect(_textAt('craze-provider-reason-native'), isNotEmpty);
      expect(_textAt('craze-provider-fix-native'), isNotEmpty);
      expect(
        _providerSelected(tester, 'grok'),
        isTrue,
        reason: 'craze\'s default, ready',
      );
      // A dimmed provider refuses the tap.
      await tester.tap(find.byKey(const ValueKey('craze-provider-cursor')));
      await _pumps(tester);
      expect(_providerSelected(tester, 'cursor'), isFalse);
      expect(_providerSelected(tester, 'grok'), isTrue);

      // craze's recent directories, one tap each.
      final recent = _recentDirs();
      expect(recent, contains(rig.work));
      await tester.tap(
        find.byKey(ValueKey('craze-recent-dir-${recent.indexOf(rig.work)}')),
      );
      await _pumps(tester);
      expect(_fieldText(tester, 'craze-create-cwd'), rig.work);

      // A fresh directory and a first prompt; Create.
      await tester.enterText(
        find.byKey(const ValueKey('craze-create-cwd')),
        sheet,
      );
      await tester.enterText(
        find.byKey(const ValueKey('craze-create-prompt')),
        'hello sheet',
      );
      await _pumps(tester);
      await _press(tester);

      // The transcript, AT ONCE, in place of the screen — its first prompt
      // taken and echoed.
      await _until(
        tester,
        () => find.byType(LaneScreen).evaluate().isNotEmpty,
        what: 'the new session\'s transcript',
      );
      final made = screen.container
          .read(crazeDraftProvider(_local.name))
          .lastCreated!;
      expect(made.ended, isFalse);
      expect(
        made.created.prompt,
        const BridgeLanePromptOutcome.accepted(),
        reason: 'the first prompt, accepted',
      );
      expect(
        tester.widget<LaneScreen>(find.byType(LaneScreen)).slug,
        made.hostId,
      );
      final ref = (
        machine: _local.name,
        kind: crazeLaneKind,
        slug: made.hostId,
      );
      bool shows(String text) =>
          screen.container
              .read(laneStateProvider(ref))
              .value
              ?.rows
              .any((r) => r.text?.contains(text) ?? false) ??
          false;
      await _until(
        tester,
        () => shows('echo: hello sheet'),
        what: 'the first prompt\'s echo in the transcript',
      );
      expect(
        find.byKey(const ValueKey('craze-create-prompt-notice')),
        findsNothing,
      );
      final sent = rig.creates.sublist(before);
      expect(sent, hasLength(1));
      expect(sent.single.dropped, isFalse);
      await _exactlyOneIn(tester, feed, sheet);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_created_row_is_in_the_feed_state_when_the_create_returns',
    (tester) async {
      // The source's nudges held back half a second: only a feed that reads
      // the source right after the create — not one that waits for the nudge
      // the create raised — has the row when the create returns. The lane
      // the screen opens next resolves its row from that state at once.
      final rig = await _rig(bins!);
      final feed = _feed(
        rig,
        crazeNudges: ({required src}) => crazeSourceNudges(src: src).asyncMap(
          (n) =>
              Future<bool>.delayed(const Duration(milliseconds: 500), () => n),
        ),
      );
      addTearDown(() => _disposeFeed(tester, feed));
      await feed.start();
      await _until(
        tester,
        () => feed.state.craze?.live ?? false,
        what: 'the craze feed live',
      );
      final created = await feed.crazeCreateSession(
        BridgeLaneCreateRequest(
          cwd: rig.work,
          prompt: 'hello at once',
          requestId: crazeNewRequestId(),
        ),
      );
      // Synchronously, before any nudge could be delivered.
      expect(
        _row(feed.state, created.session.id),
        isNotNull,
        reason: 'the created row is folded in when the create returns',
      );
      expect(created.prompt, const BridgeLanePromptOutcome.accepted());
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'an_unknown_outcome_is_retried_under_the_same_id',
    (tester) async {
      final rig = await _rig(bins!);
      final screen = await _createScreen(tester, rig);
      final dir = _mkdir('${rig.root}/w-unknown');
      final before = rig.creates.length;

      await _chooseCraze(tester);
      await tester.enterText(
        find.byKey(const ValueKey('craze-create-cwd')),
        dir,
      );
      await _pumps(tester);
      rig.dropCreates = true;
      try {
        await _press(tester);
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('craze-create-unknown'))
              .evaluate()
              .isNotEmpty,
          what: 'the sheet to report an unknown outcome',
        );
      } finally {
        rig.dropCreates = false;
      }
      final draft = screen.container.read(crazeDraftProvider(_local.name));
      final held = draft.requestId;
      expect(held, startsWith('shed-'));
      expect(draft.phase, CrazePhase.unknown);
      expect(_textAt('craze-create-unknown'), outcomeUnknownNote);
      expect(_primaryLabel(tester), 'Try again');
      expect(
        rig.creates.sublist(before),
        [(requestId: held, dropped: true), (requestId: held, dropped: true)],
        reason: 'shed-craze\'s own retry, under the same id',
      );

      await _press(tester); // Try again
      await _until(
        tester,
        () => find.byType(LaneScreen).evaluate().isNotEmpty,
        what: 'the session the first attempt started, opened',
      );
      expect(rig.creates.sublist(before), [
        (requestId: held, dropped: true),
        (requestId: held, dropped: true),
        (requestId: held, dropped: false),
      ], reason: 'Try again resumed the same request');
      await _exactlyOneIn(tester, screen.feed, dir);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_start_failure_shows_crazes_cause_and_try_again_mints_a_new_id',
    (tester) async {
      final rig = await _rig(bins!);
      final screen = await _createScreen(tester, rig);
      final dir = _mkdir('${rig.root}/w-fail');
      final before = rig.creates.length;

      await _chooseCraze(tester);
      await tester.enterText(
        find.byKey(const ValueKey('craze-create-cwd')),
        dir,
      );
      await tester.enterText(
        find.byKey(const ValueKey('craze-create-prompt')),
        'this one will not start',
      );
      await _pumps(tester);
      // grok's agent dies at its start, with two lines to say why.
      rig.setGrokAgent(rig.scriptAgent('exit-two-lines'));
      try {
        await _press(tester);
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('craze-create-cause'))
              .evaluate()
              .isNotEmpty,
          what: 'the start failure\'s cause',
        );
      } finally {
        rig.setGrokAgent(rig.grokEcho);
      }
      final cause = _textAt('craze-create-cause');
      expect(cause, contains('KEYCHAIN LOCKED'));
      expect(cause, contains('Run unlock and retry.'));
      final draft = screen.container.read(crazeDraftProvider(_local.name));
      expect(draft.refusal?.message, cause, reason: 'craze\'s cause, verbatim');
      expect(
        draft.requestId,
        isNull,
        reason: 'a definite answer ends the id\'s life',
      );
      expect(_primaryLabel(tester), 'Try again');
      expect(_fieldText(tester, 'craze-create-cwd'), dir);
      expect(
        _fieldText(tester, 'craze-create-prompt'),
        'this one will not start',
      );
      await _until(
        tester,
        () => _rowsIn(screen.feed, dir).isEmpty,
        what: 'the failed start to leave no session',
      );

      await _press(tester); // Try again, the config fixed
      await _until(
        tester,
        () => find.byType(LaneScreen).evaluate().isNotEmpty,
        what: 'the session the retry started, opened',
      );
      final sent = rig.creates.sublist(before);
      expect(sent, hasLength(2));
      expect(
        sent[1].requestId,
        isNot(sent[0].requestId),
        reason: 'a NEW id after a definite failure',
      );
      await _exactlyOneIn(tester, screen.feed, dir);
    },
    skip: skip,
    timeout: _cell,
  );

  // -------------------------------------------------------------------------
  // the transcript (CM5, §3.7.3)
  // -------------------------------------------------------------------------

  testWidgets(
    'the_transcript_seeds_sends_and_stop_ends_the_session_after_a_confirm',
    (tester) async {
      final rig = await _rig(bins!);
      final t = await _transcript(tester, rig, prompt: 'hello transcript');
      final host = t.host;
      LaneController lane() => t.controller();
      await _until(
        tester,
        () => _shows(lane().state, 'echo: hello transcript'),
        what: 'the first prompt\'s echo in the transcript',
      );

      // What the session can do, from the SNAPSHOT.
      final caps = lane().state.capabilities!;
      expect(caps.kind, 'craze');
      expect(caps.stop, isTrue, reason: 'a hub-created session can be stopped');
      expect(caps.cancel, isTrue);
      // The header reads the LIVE row: a created session runs `bypass`, and
      // the row the create answered with says nothing of it (live leg 1).
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('lane-permission')).evaluate().isNotEmpty,
        what: 'the live row\'s permission line',
      );
      expect(_textAt('lane-permission'), 'runs tools without asking');
      expect(find.byKey(const ValueKey('lane-stop')), findsOneWidget);
      // Idle: no turn to cancel.
      expect(find.byKey(const ValueKey('lane-cancel')), findsNothing);

      // A send, typed and tapped, is echoed.
      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'again please',
      );
      await _pumps(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _until(
        tester,
        () => _shows(lane().state, 'echo: again please'),
        what: 'the send\'s echo',
      );
      final controller = lane();
      final rowsBefore = controller.state.rows.length;
      // Past a roster round (craze polls its hosts about once a second and
      // flushes every 250 ms): this is the ROSTER-LISTED session's stop, whose
      // row leaves at the roster's `Removed` — after the lane has read its own
      // end. The never-listed one is the ghost-row cell's.
      await _wait(tester, const Duration(seconds: 2));

      // Stop asks first; Keep stops nothing.
      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _pumps(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lane-stop-keep')));
      await _pumps(tester);
      expect(find.byKey(const ValueKey('lane-stop-confirm')), findsNothing);
      expect(controller.state.ended, isFalse);

      // Every state from the Stop on: a final end is given up on AT ONCE —
      // never put on the re-open ladder first, which the row's later
      // `Removed` would then cut short and hide.
      final afterStop = <LaneState>[];
      final watching = controller.updates.listen(afterStop.add);
      addTearDown(watching.cancel);
      await tester.tap(find.byKey(const ValueKey('lane-stop')));
      await _pumps(tester);
      await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
      await _until(
        tester,
        () => controller.state.abandoned,
        what: 'the stopped session\'s lane to end for good',
      );
      expect(
        afterStop.where((s) => s.retrying),
        isEmpty,
        reason: 'session_closed is final: no re-open was ever scheduled',
      );
      expect(controller.state.stale, laneSessionClosed);
      expect(
        _textAt('lane-stale'),
        laneSessionClosed,
        reason: 'ended — never "reconnecting…"',
      );
      expect(controller.state.stopError, isNull);
      expect(
        controller.state.rows.length,
        greaterThanOrEqualTo(rowsBefore),
        reason: 'the transcript stays',
      );
      await _until(
        tester,
        () => _row(t.feed.state, host) == null,
        what: 'the stopped session\'s row to leave',
      );
      // Past the re-open ladder's first step: a final end re-opens nothing.
      await _wait(tester, const Duration(seconds: 3));
      expect(t.source.crazeOpens, [host], reason: 'never re-opened');
      expect(controller.state.abandoned, isTrue);
      expect((await liveCounters()).activeLanes, BigInt.zero);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'asks_are_answered_on_the_screen_by_their_offered_ids',
    (tester) async {
      final rig = await _rig(bins!);
      await rig.fakeHost(_fake, _fakeSession);
      final t = await _transcript(tester, rig, host: _fake);
      LaneController lane() => t.controller();

      rig.op({
        'name': 'permission',
        'id': 'perm-1',
        'tool': 'Shell',
        'options': [
          {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
          {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
        ],
      });
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('lane-option-deny'))
            .evaluate()
            .isNotEmpty,
        what: 'the permission card',
      );
      expect(
        find.byKey(const ValueKey('lane-option-allow')),
        findsOneWidget,
        reason: 'craze\'s options, in craze\'s order, by their own ids',
      );
      await tester.tap(find.byKey(const ValueKey('lane-option-deny')));
      await _until(
        tester,
        () => lane().state.approvals.isEmpty,
        what: 'the permission resolved',
      );

      rig.op({
        'name': 'question',
        'id': 'q-1',
        'title': 'Pick',
        'questions': [
          {
            'id': 'lang',
            'prompt': 'Which language?',
            'options': [
              {'id': 'rs', 'label': 'Rust'},
              {'id': 'go', 'label': 'Go'},
            ],
          },
        ],
      });
      await _until(
        tester,
        () => lane().state.approvals.any((a) => a.id == 'q-1'),
        what: 'the question card',
      );
      final question = lane().state.approvals.singleWhere((a) => a.id == 'q-1');
      expect(question.questions.single.custom, isFalse);
      // One question, one choice, no free text: one tap is the answer.
      await tester.tap(find.widgetWithText(FilterChip, 'Rust'));
      await _until(
        tester,
        () => _shows(lane().state, '? Which language? → Rust'),
        what: 'the question\'s note',
      );

      rig.op({
        'name': 'plan',
        'id': 'plan-1',
        'planName': 'Refactor',
        'overview': 'Split it',
        'plan': '1. split',
      });
      await _until(
        tester,
        () => lane().state.approvals.any((a) => a.id == 'plan-1'),
        what: 'the plan card',
      );
      final plan = lane().state.approvals.singleWhere((a) => a.id == 'plan-1');
      expect(plan.options.map((o) => o.id), contains('accept'));
      await tester.tap(find.byKey(const ValueKey('lane-option-accept')));
      await _until(
        tester,
        () => _shows(lane().state, 'plan Refactor → accepted'),
        what: 'the plan\'s note',
      );
      expect(lane().state.approvals, isEmpty);
      expect(lane().state.approvalErrors, isEmpty);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'cancel_is_offered_while_a_turn_runs_and_ends_it',
    (tester) async {
      final rig = await _rig(bins!);
      await rig.fakeHost(_fake, _fakeSession);
      final t = await _transcript(tester, rig, host: _fake);
      LaneController lane() => t.controller();
      expect(lane().state.capabilities?.cancel, isTrue);
      expect(
        find.byKey(const ValueKey('lane-cancel')),
        findsNothing,
        reason: 'idle: nothing to cancel',
      );

      rig.op({'name': 'hang_next'});
      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'a long one',
      );
      await _pumps(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _until(
        tester,
        () => find.byKey(const ValueKey('lane-cancel')).evaluate().isNotEmpty,
        what: 'the running turn\'s Cancel',
      );
      expect(lane().state.activity, BridgeRcActivity.working);
      await tester.tap(find.byKey(const ValueKey('lane-cancel')));
      await _until(
        tester,
        () => lane().state.activity != BridgeRcActivity.working,
        what: 'the cancelled turn to end',
      );
      expect(lane().state.composerError, isNull);
      await _until(
        tester,
        () => find.byKey(const ValueKey('lane-cancel')).evaluate().isEmpty,
        what: 'Cancel gone with the turn',
      );
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_killed_lane_connection_resumes_silently',
    (tester) async {
      final rig = await _rig(bins!);
      final t = await _transcript(tester, rig, prompt: 'before the drop');
      final host = t.host;
      final controller = t.controller();
      await _until(
        tester,
        () =>
            _shows(controller.state, 'echo: before the drop') &&
            controller.state.stale == null,
        what: 'the transcript seeded',
      );
      final handle = controller.handle;
      expect(handle, isNotNull);
      final generation = controller.state.generation;
      final seqs = [for (final r in controller.state.rows) r.seq];
      final readsBefore = t.source.reads.length;

      // The LANE's own connection: the bridge its client asked the hub to
      // splice to this host — not the feed tunnel's listener, not the roster.
      final killed = rig.laneBridge(host);
      expect(killed, isNot(same(rig.rosterBridge())));
      rig.holdCrazeDials = Completer<void>();
      try {
        rig.killBridge(killed);
        await killed.exitCode.timeout(const Duration(seconds: 10));
        await _until(
          tester,
          () =>
              controller.state.stale != null &&
              find.byKey(const ValueKey('lane-stale')).evaluate().isNotEmpty,
          what: 'the lane to say it is reconnecting',
        );
        expect(_textAt('lane-stale'), startsWith('reconnecting…'));
        expect(controller.state.ended, isFalse);

        // A few seconds with no way back: still the same lane, still waiting.
        await _wait(tester, const Duration(seconds: 3));
        expect(controller.state.ended, isFalse);
        expect(controller.state.stale, isNotNull);
        expect(_textAt('lane-stale'), startsWith('reconnecting…'));
        expect(controller.handle, same(handle));
      } finally {
        rig.holdCrazeDials!.complete();
        rig.holdCrazeDials = null;
      }

      await _until(
        tester,
        () => controller.state.stale == null,
        what: 'the resume to clear the banner',
      );
      expect(find.byKey(const ValueKey('lane-stale')), findsNothing);
      expect(controller.handle, same(handle), reason: 'the SAME lane handle');
      expect(t.source.crazeOpens, [host], reason: 'never re-opened');
      expect(
        controller.state.generation,
        generation,
        reason: 'no reseed: the generation is unchanged',
      );
      final reads = t.source.reads.sublist(readsBefore);
      expect(
        reads.where((r) => r.full),
        isEmpty,
        reason: 'no Reset: every read across the outage was a delta',
      );
      expect(reads.map((r) => r.generation).toSet(), {generation});
      expect(
        reads.any((r) => r.stale != null && !r.ended),
        isTrue,
        reason: 'the outage was read as stale, never as ended',
      );
      expect(
        [for (final r in controller.state.rows) r.seq].take(seqs.length),
        seqs,
        reason: 'the rows read before the drop are the rows kept',
      );
      final redial = rig.laneBridge(host);
      expect(
        redial,
        isNot(same(killed)),
        reason: 'a new connection carries it',
      );

      // And it is live: a send lands.
      await tester.enterText(
        find.byKey(const ValueKey('lane-input')),
        'after the drop',
      );
      await _pumps(tester);
      await tester.tap(find.byKey(const ValueKey('lane-send')));
      await _until(
        tester,
        () => _shows(controller.state, 'echo: after the drop'),
        what: 'the send after the resume to land',
      );
      expect(controller.state.composerError, isNull);
      expect(controller.handle, same(handle));
      expect(controller.state.generation, generation);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_session_created_and_stopped_at_once_leaves_the_rows',
    (tester) async {
      // Amendment A16, the ghost row. A session stopped before any roster
      // frame lists it gets no `Removed` (craze sends one only for a host it
      // has sent), so only the source's `on_created_gone` — the lane telling
      // the source its session ended — can take its created row away. The
      // roster's own bridge is FROZEN for the whole create→stop, and the cell
      // proves it: stopped (`/proc` state `T`) before the create begins, still
      // alive and stopped at the moment the row leaves, and never replaced —
      // so no roster frame can have listed the session or removed it.
      final rig = await _rig(bins!);
      final t = await _feedGraph(tester, rig);
      final roster = rig.rosterBridge();
      final rosterConnections = rig.rosterConnections;
      await rig.pause(roster);
      expect(
        rig.isPaused(roster),
        isTrue,
        reason: 'the roster is frozen before the create begins',
      );
      late String host;
      bool? frozenAtDeparture;
      try {
        final created = await t.feed.crazeCreateSession(
          BridgeLaneCreateRequest(
            cwd: rig.work,
            requestId: crazeNewRequestId(),
          ),
        );
        host = created.session.id;
        expect(_row(t.feed.state, host), isNotNull, reason: 'listed at once');

        // Its transcript, and Stop the moment there is one to press.
        await _showLane(tester, t.container, host);
        await _until(
          tester,
          () => find.byKey(const ValueKey('lane-stop')).evaluate().isNotEmpty,
          what: 'the created session\'s Stop',
        );
        await tester.tap(find.byKey(const ValueKey('lane-stop')));
        await _pumps(tester);
        await tester.tap(find.byKey(const ValueKey('lane-stop-session')));
        await _until(tester, () {
          final gone = _row(t.feed.state, host) == null;
          // Read at the very moment the departure is first seen.
          if (gone) frozenAtDeparture ??= rig.isPaused(roster);
          return gone;
        }, what: 'the stopped session\'s row to leave with no roster frame');
        expect(
          frozenAtDeparture,
          isTrue,
          reason:
              'the roster bridge was alive and STOPPED when the row left: '
              'no roster frame carried the departure',
        );
        expect(
          rig.rosterConnections,
          rosterConnections,
          reason: 'no replacement roster connection was opened',
        );
        expect(rig.rosterBridge(), same(roster));
        final controller = t.container.read(
          laneControllerProvider((
            machine: _local.name,
            kind: crazeLaneKind,
            slug: host,
          )),
        );
        await _until(
          tester,
          () => controller.state.abandoned,
          what: 'the lane to end for good',
        );
        expect(t.source.crazeOpens, [
          host,
        ], reason: 'a stopped session is never re-opened');
        expect(rig.isPaused(roster), isTrue, reason: 'frozen throughout');
      } finally {
        rig.resume(roster);
      }

      // The roster catches up: whatever it says now, the row stays gone.
      await _wait(tester, const Duration(seconds: 3));
      expect(_row(t.feed.state, host), isNull);
      expect(
        rig.rosterConnections,
        rosterConnections,
        reason: 'the same roster connection, resumed — never a replacement',
      );
      expect((await liveCounters()).activeLanes, BigInt.zero);
    },
    skip: skip,
    timeout: _cell,
  );

  // -------------------------------------------------------------------------
  // settings (CM6, §3.10)
  // -------------------------------------------------------------------------

  testWidgets(
    'the_sheet_renders_crazes_settings_and_a_model_change_redraws_the_options',
    (tester) async {
      _tall(tester);
      final rig = await _rig(bins!);
      final t = await _permodel(tester, rig);
      expect(_chip(), 'Grok 4.6 · High · fast');
      await _openSettings(tester);
      expect(_sheetRows(), [
        'model:model',
        'config:effort',
        'config:fast',
        'mode:mode',
      ]);
      expect(_values('model:model'), _permodelModels);
      expect(_shown(tester, 'model:model'), 'grok-4.6');
      expect(_values('config:effort'), ['low', 'medium', 'high', 'xhigh']);
      expect(_shown(tester, 'config:effort'), 'high');
      expect(_shown(tester, 'config:fast'), 'true');
      expect(_values('mode:mode'), ['agent', 'plan', 'ask']);
      expect(
        find.byKey(const ValueKey('lane-settings-meter')),
        findsNothing,
        reason: 'an ACP session reports no usage: no context meter',
      );

      // The model change, with the agent holding its answer: PENDING, and
      // no optimistic value.
      await t.gate.hold();
      await _pressSetting(tester, 'model:model', 'claude-opus-5');
      await _until(
        tester,
        () => _markOf('model:model') == pendingText,
        what: 'the model row pending',
      );
      expect(_shown(tester, 'model:model'), 'grok-4.6');
      expect(rig.sets.last.setting, {
        'kind': 'model',
        'value': 'claude-opus-5',
      });
      await t.gate.release();
      t.gate.open();
      await _until(
        tester,
        () =>
            _shown(tester, 'model:model') == 'claude-opus-5' &&
            _markOf('model:model') == null,
        what: 'the model change, from the session\'s next Settings',
      );
      // claude-opus-5's OWN options: thinking and effort (thought_level)
      // before context and fast (model_config), effort now five values and
      // so a list.
      expect(_sheetRows(), [
        'model:model',
        'config:thinking',
        'config:effort',
        'config:context',
        'config:fast',
        'mode:mode',
      ]);
      expect(_values('config:effort'), hasLength(5));
      expect(_isList(tester, 'config:effort'), isTrue);
      expect(_values('model:model').first, 'claude-opus-5', reason: 'first');
      expect(_chip(), 'Claude Opus 5 · High');

      // An option and a mode, each from the session's own next Settings —
      // the option bound to the model the sheet now shows.
      await _pressSetting(tester, 'config:effort', 'low');
      await _until(
        tester,
        () => _shown(tester, 'config:effort') == 'low',
        what: 'the option change',
      );
      await _pressSetting(tester, 'mode:mode', 'plan');
      await _until(
        tester,
        () => _shown(tester, 'mode:mode') == 'plan',
        what: 'the mode change',
      );
      expect(_chip(), 'Claude Opus 5 · Low');
      final sent = [for (final e in rig.sets) e.setting];
      expect(
        sent,
        anyElement(
          equals({
            'kind': 'config',
            'id': 'effort',
            'value': 'low',
            'forModel': 'claude-opus-5',
          }),
        ),
      );
      expect(sent, anyElement(equals({'kind': 'mode', 'value': 'plan'})));
      expect(_sheetMarks(), isEmpty);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_stale_model_refusal_is_inline_on_its_row_and_the_retry_is_a_new_command',
    (tester) async {
      _tall(tester);
      final rig = await _rig(bins!);
      final t = await _permodel(tester, rig);
      await _openSettings(tester);
      expect(_shown(tester, 'model:model'), 'grok-4.6');

      final other = await rig.client();
      try {
        final sid = await other.connect(t.host);
        await t.gate.hold();
        // Another client moves the session to claude-opus-5; the agent holds
        // that change.
        final moved = other.send('session.set', {
          'sessionId': sid,
          'commandId': '1',
          'setting': {'kind': 'model', 'value': 'claude-opus-5'},
        });
        await _until(
          tester,
          () => CrazeRig.agentSets(t.calls).lastOrNull == 'model=claude-opus-5',
          what: 'the other client\'s move at the agent',
        );
        // The sheet still shows grok-4.6: the effort press is chosen on it,
        // and bound to it.
        final before = rig.sets.length;
        await _pressSetting(tester, 'config:effort', 'low');
        await _until(
          tester,
          () => rig.sets.length > before,
          what: 'the sheet\'s change on the wire',
        );
        final chosen = rig.sets.last;
        expect(chosen.setting, {
          'kind': 'config',
          'id': 'effort',
          'value': 'low',
          'forModel': 'grok-4.6',
        });
        expect(_markOf('config:effort'), pendingText);
        // Let the change reach craze's queue behind the held move.
        await _wait(tester, const Duration(milliseconds: 500));
        await t.gate.release();
        await _until(
          tester,
          () => _markOf('config:effort') == staleModelText,
          what: 'the stale_model refusal on the effort row',
        );
        expect(
          (await moved.timeout(const Duration(seconds: 30)))['value'],
          'claude-opus-5',
        );
        t.gate.open();
        await _until(
          tester,
          () => _shown(tester, 'model:model') == 'claude-opus-5',
          what: 'the sheet redrawn on the session\'s model',
        );
        expect(
          _markOf('config:effort'),
          staleModelText,
          reason: 'the refusal stays on its row until the row is pressed',
        );
        for (final row in _sheetRows()) {
          if (row != 'config:effort') {
            expect(_markOf(row), isNull, reason: 'only $row\'s own');
          }
        }
        expect(
          CrazeRig.agentSets(t.calls),
          isNot(contains('effort=low')),
          reason: 'a change chosen for another model never reached the agent',
        );

        // The retry: a NEW command, bound to the model shown now.
        await _pressSetting(tester, 'config:effort', 'low');
        await _until(
          tester,
          () =>
              _shown(tester, 'config:effort') == 'low' &&
              _markOf('config:effort') == null,
          what: 'the retry taking',
        );
        final retry = rig.sets.last;
        expect(retry.setting['forModel'], 'claude-opus-5');
        expect(
          retry.commandId,
          isNot(chosen.commandId),
          reason: 'the retry is a NEW command',
        );
      } finally {
        await other.close();
      }
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'an_option_is_bound_to_the_model_the_sheet_displayed',
    (tester) async {
      // Amendment A13, live: another client moves the session to
      // composer-2.5 and the lane FOLDS it, while the screen still shows
      // grok-4.6 (the view held — the frame between the adapter folding a
      // change and the screen drawing it). The fast press — an option
      // composer-2.5 also has — goes out bound to grok-4.6, and craze refuses
      // it `stale_model`, inline on its row, rather than apply it to
      // composer-2.5. It never reaches the agent.
      _tall(tester);
      final rig = await _rig(bins!);
      final view = _HeldViewSource();
      final t = await _permodel(tester, rig, recording: view);
      await _openSettings(tester);
      expect(_shown(tester, 'model:model'), 'grok-4.6');
      expect(_shown(tester, 'config:fast'), 'true');

      final other = await rig.client();
      try {
        final sid = await other.connect(t.host);
        view.hold();
        await other.call('session.set', {
          'sessionId': sid,
          'commandId': '1',
          'setting': {'kind': 'model', 'value': 'composer-2.5'},
        });
        await _until(
          tester,
          () => view.latest?.settings?.model == 'composer-2.5',
          what: 'the move folded by the lane',
        );
        expect(
          _shown(tester, 'model:model'),
          'grok-4.6',
          reason: 'the sheet still shows grok-4.6',
        );
        final before = rig.sets.length;
        await _pressSetting(tester, 'config:fast', 'false');
        await _until(
          tester,
          () => _markOf('config:fast') == staleModelText,
          what: 'the stale_model refusal on the fast row',
        );
        final sent = rig.sets.sublist(before);
        expect(sent, hasLength(1));
        expect(sent.single.setting, {
          'kind': 'config',
          'id': 'fast',
          'value': 'false',
          'forModel': 'grok-4.6',
        });
        expect(
          CrazeRig.agentSets(t.calls),
          isNot(contains('fast=false')),
          reason: 'an option chosen on grok-4.6 never reached composer-2.5',
        );
      } finally {
        view.release();
        await other.close();
      }
      await _until(
        tester,
        () => _shown(tester, 'model:model') == 'composer-2.5',
        what: 'the sheet, released, showing the move',
      );
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_change_made_by_another_client_appears_in_the_open_sheet',
    (tester) async {
      _tall(tester);
      final rig = await _rig(bins!);
      final t = await _permodel(tester, rig);
      await _openSettings(tester);
      expect(_shown(tester, 'mode:mode'), 'agent');
      expect(_shown(tester, 'config:effort'), 'high');

      final other = await rig.client();
      try {
        final sid = await other.connect(t.host);
        await other.call('session.set', {
          'sessionId': sid,
          'commandId': '1',
          'setting': {'kind': 'mode', 'value': 'plan'},
        });
        await other.call('session.set', {
          'sessionId': sid,
          'commandId': '2',
          'setting': {
            'kind': 'config',
            'id': 'effort',
            'value': 'low',
            'forModel': 'grok-4.6',
          },
        });
      } finally {
        await other.close();
      }
      await _until(
        tester,
        () =>
            _shown(tester, 'mode:mode') == 'plan' &&
            _shown(tester, 'config:effort') == 'low',
        what: 'the other client\'s changes in the open sheet',
      );
      expect(_chip(), 'Grok 4.6 · Low · fast');
      expect(rig.sets, isEmpty, reason: 'nothing was pressed here');
      expect(_sheetMarks(), isEmpty);
    },
    skip: skip,
    timeout: _cell,
  );

  testWidgets(
    'a_change_lost_to_a_drop_is_not_confirmed_until_the_next_settings',
    (tester) async {
      _tall(tester);
      final rig = await _rig(bins!);
      final t = await _permodel(tester, rig);
      final controller = t.controller();
      await _openSettings(tester);
      expect(_shown(tester, 'config:fast'), 'true');
      final handle = controller.handle;

      // The lane's bridge is cut once craze has the change, and its redial
      // held: the answer is lost, and the lane cannot come back yet.
      rig.dropSets = true;
      rig.holdCrazeDials = Completer<void>();
      try {
        await _pressSetting(tester, 'config:fast', 'false');
        await _until(
          tester,
          () => _markOf('config:fast') == notConfirmedText,
          what: 'the fast row not confirmed',
        );
        expect(
          _shown(tester, 'config:fast'),
          'true',
          reason: 'the old value until the session says otherwise',
        );
        await _until(
          tester,
          () => controller.state.stale != null,
          what: 'the lane to say it is reconnecting',
        );
        // A while with no way back: still not confirmed, never applied.
        await _wait(tester, const Duration(seconds: 2));
        expect(_markOf('config:fast'), notConfirmedText);
        expect(_shown(tester, 'config:fast'), 'true');
        expect(
          CrazeRig.agentSets(t.calls),
          contains('fast=false'),
          reason: 'craze ran the change',
        );
      } finally {
        rig.dropSets = false;
        rig.holdCrazeDials!.complete();
        rig.holdCrazeDials = null;
      }

      // The lane resumes, and its next Settings — the change DID run —
      // replaces the mark with the real value.
      await _until(
        tester,
        () =>
            _markOf('config:fast') == null &&
            _shown(tester, 'config:fast') == 'false',
        what: 'the resume\'s Settings replacing the mark',
      );
      expect(controller.handle, same(handle), reason: 'a silent resume');
      await _wait(tester, const Duration(seconds: 1));
      final fast = [
        for (final e in rig.sets)
          if (e.setting['id'] == 'fast') e,
      ];
      expect(fast, hasLength(1), reason: 'never resent');
      expect(fast.single.dropped, isTrue);
      expect(
        CrazeRig.agentSets(t.calls).where((c) => c == 'fast=false'),
        hasLength(1),
        reason: 'the agent was asked once',
      );
    },
    skip: skip,
    timeout: _cell,
  );
}

// ---------------------------------------------------------------------------
// the rig
// ---------------------------------------------------------------------------

/// A rig whose teardown — every craze process of its own gone, checked — is
/// registered before anything can fail.
Future<CrazeRig> _rig(
  CrazeBins bins, {
  CrazePath path = CrazePath.recipe,
}) async {
  final rig = await CrazeRig.start(bins, path: path);
  addTearDown(() async {
    final left = await rig.teardown();
    expect(left, isEmpty, reason: 'craze processes left behind');
  });
  return rig;
}

/// A feed on [_local] whose tunnels are [rig]'s. Built directly: no SSH key,
/// no host keys, nothing dialled.
MachineFeed _feed(
  CrazeRig rig, {
  TunnelOpen? openTunnel,
  CrazeSourceOpen? openCrazeSource,
  CrazeSourceNudges? crazeNudges,
}) => MachineFeed(
  machine: _local,
  identities: const [],
  hostKeys: HostKeyStore(),
  entitlements: RoostBootstrapEntitlements(),
  openTunnel: openTunnel ?? rig.tunnelOpen,
  openCrazeSource: openCrazeSource,
  crazeNudges: crazeNudges,
);

/// A craze source seam whose opens can fail or wait: what the start-in-flight
/// cells hold a start on. Past [failNext] and [hold], an open is the real one.
class _HeldSources {
  int opens = 0;

  /// The next open throws, as a source that would not open.
  bool failNext = false;

  /// While set, every open waits on it ([waiting] says one is) — a start held
  /// mid-flight for as long as a cell needs.
  Completer<void>? hold;
  bool waiting = false;

  void release() {
    final h = hold;
    hold = null;
    h?.complete();
  }

  Future<BridgeCrazeSource> open({
    required String machine,
    required int port,
  }) async {
    opens++;
    if (failNext) {
      failNext = false;
      throw StateError('the craze source would not open');
    }
    final h = hold;
    if (h != null) {
      waiting = true;
      await h.future;
      waiting = false;
    }
    return crazeSourceOpen(machine: machine, port: port);
  }
}

/// The create screen on [_local], over the real provider graph with [rig]'s
/// tunnels — the craze feed live before it returns. With [show] false the
/// screen is not up yet ([_showCreateScreen] puts it up).
///
/// This harness has no roost, so craze is the only kind the screen offers and
/// it opens straight onto the craze sheet — which reads its options then.
Future<({ProviderContainer container, MachineFeed feed})> _createScreen(
  WidgetTester tester,
  CrazeRig rig, {
  bool show = true,
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      machinesProvider.overrideWith((ref) async => const [_local]),
      identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
      machineTunnelOpenProvider.overrideWithValue(rig.tunnelOpen),
    ],
  );
  addTearDown(() => _dispose(tester, container));
  if (show) await _showCreateScreen(tester, container);
  final feedState = container.listen(
    machineFeedProvider(_local.name),
    (_, _) {},
    fireImmediately: true,
  );
  await _until(
    tester,
    () => feedState.read().value?.craze?.live ?? false,
    what: 'the craze feed live',
  );
  return (
    container: container,
    feed: container.read(machineFeedControllerProvider(_local.name)),
  );
}

Future<void> _showCreateScreen(
  WidgetTester tester,
  ProviderContainer container,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: shedLightTheme,
      home: CreateRcScreen(target: MachineRcTarget(machineName: _local.name)),
    ),
  ),
);

/// Pick the craze choice and wait for craze's providers.
Future<void> _chooseCraze(WidgetTester tester) async {
  const choice = ValueKey('createrc-kind-craze');
  await _until(
    tester,
    () => find.byKey(choice).evaluate().isNotEmpty,
    what: 'the craze choice offered',
  );
  await tester.tap(find.byKey(choice));
  await _until(
    tester,
    () =>
        find.byKey(const ValueKey('craze-provider-grok')).evaluate().isNotEmpty,
    what: 'craze\'s providers on the sheet',
  );
}

/// Press the sheet's primary button (Create / Try again).
Future<void> _press(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('craze-create-submit'));
  await tester.ensureVisible(button);
  await _pumps(tester);
  await tester.tap(button);
  await _pumps(tester);
}

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// The provider rows' keys, in the order the sheet shows them.
List<String> _providerRows() => find
    .byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          RegExp(r'^craze-provider-[a-z]+$').hasMatch(k.value);
    })
    .evaluate()
    .map((e) => (e.widget.key! as ValueKey<String>).value)
    .toList();

bool _providerSelected(WidgetTester tester, String provider) => tester
    .widget<Semantics>(
      find
          .descendant(
            of: find.byKey(ValueKey('craze-provider-$provider')),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .selected!;

/// craze's recent directories, as the sheet shows them.
List<String> _recentDirs() {
  final dirs = <String>[];
  for (var i = 0; ; i++) {
    final chip = find.byKey(ValueKey('craze-recent-dir-$i'));
    if (chip.evaluate().isEmpty) return dirs;
    dirs.add(
      (find
                  .descendant(of: chip, matching: find.byType(Text))
                  .evaluate()
                  .single
                  .widget
              as Text)
          .data!,
    );
  }
}

String _textAt(String key) {
  final w = find.byKey(ValueKey(key)).evaluate().single.widget;
  return switch (w) {
    final Text t => t.data!,
    final SelectableText t => t.data!,
    final Container c => (c.child! as Text).data!,
    _ => throw StateError('no text at $key'),
  };
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

String _primaryLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('craze-create-submit')),
        matching: find.byType(Text),
      ),
    )
    .data!;

String _mkdir(String path) {
  Directory(path).createSync();
  return path;
}

List<CrazeMachineRow> _rowsIn(MachineFeed feed, String cwd) => [
  for (final r in feed.state.rows)
    if (r is CrazeMachineRow && r.session.cwd == cwd) r,
];

/// The one craze session in [cwd] — waited for, then given two seconds for a
/// second (which must never come) to be listed too.
Future<void> _exactlyOneIn(
  WidgetTester tester,
  MachineFeed feed,
  String cwd,
) async {
  await _until(
    tester,
    () => _rowsIn(feed, cwd).isNotEmpty,
    what: 'the session in $cwd listed',
  );
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    _rowsIn(feed, cwd).map((r) => r.session.id).toList(),
    hasLength(1),
    reason: 'exactly one session in $cwd',
  );
}

/// Dispose [feed] and wait for every bridge counter to come back — so a cell
/// never hands the next one a count of its own.
Future<void> _disposeFeed(WidgetTester tester, MachineFeed feed) async {
  await feed.dispose().timeout(const Duration(seconds: 20));
  await _zero(tester, what: 'the feed\'s teardown');
}

/// Unmount, dispose the container (its feed's `onDispose`), and wait for the
/// counters — Riverpod does not await the teardown it starts.
Future<void> _dispose(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await _zero(tester, what: 'the container\'s teardown');
}

/// Wait until every counter a feed can hold is zero, or fail naming them.
Future<void> _zero(WidgetTester tester, {required String what}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  late BridgeLiveCounters c;
  while (DateTime.now().isBefore(deadline)) {
    c = await liveCounters();
    if (c.activeCrazeSources == BigInt.zero &&
        c.activeCrazeForwarders == BigInt.zero &&
        c.pendingCrazeCalls == BigInt.zero &&
        c.activeLanes == BigInt.zero &&
        c.activeLaneForwarders == BigInt.zero &&
        c.activeWatchers == BigInt.zero &&
        c.activeForwarders == BigInt.zero) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(
    '$what left counters: sources=${c.activeCrazeSources} '
    'forwarders=${c.activeCrazeForwarders} calls=${c.pendingCrazeCalls} '
    'lanes=${c.activeLanes} watchers=${c.activeWatchers} '
    'watcherForwarders=${c.activeForwarders}',
  );
}

/// The craze tunnel's port no longer accepts: the tunnel went with the feed.
Future<void> _refused(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
    ).timeout(const Duration(seconds: 5));
    socket.destroy();
    fail('the craze tunnel\'s port $port still accepts after the teardown');
  } on SocketException {
    // Refused: the listener is gone.
  }
}

/// Poll [done] while letting real time pass, or fail naming [what].
Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (done()) {
      // Let the state reach the widget tree too.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done()) fail('timed out waiting for $what');
}

CrazeMachineRow? _row(MachineFeedState? state, String hostId) {
  for (final row in state?.rows ?? const <MachineRow>[]) {
    if (row is CrazeMachineRow && row.session.id == hostId) return row;
  }
  return null;
}

/// A roost tab as the watcher would report it.
BridgeRcSession _tab(int tabId, BridgeRcKind kind, {String? rcId}) =>
    BridgeRcSession(
      host: '',
      shed: '',
      slug: '$tabId',
      displayName: 'tab$tabId',
      kind: kind,
      state: BridgeRcState.ready,
      managed: true,
      attention: false,
      tabId: tabId,
      rcId: rcId,
    );

/// The phone's lane bridge, recorded: every craze open (by hostId) and every
/// read's shape — what the resume cell checks "no re-open" and "no reseed"
/// against. A pass-through to [BridgeLaneSource] otherwise.
class _RecordingSource implements LaneSource {
  final _bridge = const BridgeLaneSource();

  /// Every craze lane opened, by hostId, in order.
  final crazeOpens = <String>[];

  /// Every snapshot read, in order.
  final reads = <({bool full, BigInt generation, String? stale, bool ended})>[];

  @override
  Future<LaneHandle> open(BridgeLaneSpec spec) => _bridge.open(spec);

  @override
  Future<LaneHandle> openCraze(CrazeLaneOpen open, String hostId) {
    crazeOpens.add(hostId);
    return _bridge.openCraze(open, hostId);
  }

  @override
  Stream<bool> nudges(LaneHandle handle) => _bridge.nudges(handle);

  @override
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq) {
    final snap = _bridge.snapshot(handle, sinceSeq);
    reads.add((
      full: snap.full,
      generation: snap.generation,
      stale: snap.stale,
      ended: snap.ended,
    ));
    return snap;
  }

  @override
  Future<void> send(
    LaneHandle handle, {
    required String text,
    required BridgeSendMode mode,
  }) => _bridge.send(handle, text: text, mode: mode);

  @override
  Future<void> cancel(LaneHandle handle) => _bridge.cancel(handle);

  @override
  Future<void> answer(
    LaneHandle handle, {
    required String approvalId,
    required BridgeLaneAnswer answer,
  }) => _bridge.answer(handle, approvalId: approvalId, answer: answer);

  @override
  Future<void> stop(LaneHandle handle) => _bridge.stop(handle);

  @override
  Future<void> set(LaneHandle handle, BridgeLaneSettingChange change) =>
      _bridge.set(handle, change);

  @override
  void close(LaneHandle handle) => _bridge.close(handle);
}

/// [_RecordingSource] with the desktop's view hold (`ui.hold_lane_view`): while
/// [hold] is set, every read still goes to the bridge — the lane's fold moves
/// on, and [latest] says where to — but the controller is handed the view as
/// it stood when the hold began, with no new rows. What a person sees in the
/// moment between the adapter folding a change and the screen drawing it,
/// held open so a cell can press inside it. [release] lets the screen catch
/// up.
class _HeldViewSource extends _RecordingSource {
  bool _held = false;
  BridgeLaneSnapshot? _shown;

  /// The bridge's own latest read — the lane's fold, whatever the screen
  /// shows.
  BridgeLaneSnapshot? latest;

  /// One nudge stream per open lane, so [release] can ask for a read.
  final _kick = StreamController<bool>.broadcast();

  void hold() => _held = true;

  void release() {
    _held = false;
    _kick.add(true);
  }

  @override
  Stream<bool> nudges(LaneHandle handle) {
    final out = StreamController<bool>();
    final real = _bridge
        .nudges(handle)
        .listen(out.add, onError: out.addError, onDone: out.close);
    final kicks = _kick.stream.listen(out.add);
    out.onCancel = () async {
      await kicks.cancel();
      await real.cancel();
    };
    return out.stream;
  }

  @override
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq) {
    final read = super.snapshot(handle, sinceSeq);
    latest = read;
    if (!_held) return _shown = read;
    final shown = _shown ?? read;
    return BridgeLaneSnapshot(
      messages: const [],
      full: false,
      activity: shown.activity,
      session: shown.session,
      generation: shown.generation,
      stale: shown.stale,
      ended: shown.ended,
      capabilities: shown.capabilities,
      settings: shown.settings,
      settingsFrames: shown.settingsFrames,
      approvals: shown.approvals,
    );
  }
}

/// The provider graph over [rig]'s tunnels, with the lane bridge recorded,
/// and the craze feed live before it returns.
Future<
  ({ProviderContainer container, MachineFeed feed, _RecordingSource source})
>
_feedGraph(
  WidgetTester tester,
  CrazeRig rig, {
  _RecordingSource? recording,
}) async {
  final source = recording ?? _RecordingSource();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      machinesProvider.overrideWith((ref) async => const [_local]),
      identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
      machineTunnelOpenProvider.overrideWithValue(rig.tunnelOpen),
      laneSourceProvider.overrideWithValue(source),
    ],
  );
  addTearDown(() => _dispose(tester, container));
  final feedState = container.listen(
    machineFeedProvider(_local.name),
    (_, _) {},
    fireImmediately: true,
  );
  await _until(
    tester,
    () => feedState.read().value?.craze?.live ?? false,
    what: 'the craze feed live',
  );
  return (
    container: container,
    feed: container.read(machineFeedControllerProvider(_local.name)),
    source: source,
  );
}

/// The transcript screen for [hostId], over [container]'s graph — what the
/// session row's Transcript pill pushes.
Future<void> _showLane(
  WidgetTester tester,
  ProviderContainer container,
  String hostId,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: shedLightTheme,
      home: LaneScreen(
        machine: _local.name,
        kind: crazeLaneKind,
        slug: hostId,
        title: 'craze $hostId',
      ),
    ),
  ),
);

/// A craze session's transcript on screen and SEEDED: [host]'s (a fake host's
/// hostId), or — with [prompt] — a session created for the cell with that
/// first prompt.
Future<
  ({
    ProviderContainer container,
    MachineFeed feed,
    _RecordingSource source,
    String host,
    LaneController Function() controller,
  })
>
_transcript(
  WidgetTester tester,
  CrazeRig rig, {
  String? host,
  String? prompt,
}) async {
  final g = await _feedGraph(tester, rig);
  var id = host;
  if (id == null) {
    final created = await g.feed.crazeCreateSession(
      BridgeLaneCreateRequest(
        cwd: rig.work,
        prompt: prompt,
        requestId: crazeNewRequestId(),
      ),
    );
    expect(created.prompt, const BridgeLanePromptOutcome.accepted());
    id = created.session.id;
  } else {
    await _until(
      tester,
      () => _row(g.feed.state, host!) != null,
      what: 'the row of $host',
    );
  }
  final hostId = id;
  await _showLane(tester, g.container, hostId);
  LaneController controller() => g.container.read(
    laneControllerProvider((
      machine: _local.name,
      kind: crazeLaneKind,
      slug: hostId,
    )),
  );
  await _until(
    tester,
    () =>
        controller().isOpen &&
        controller().state.generation > BigInt.zero &&
        controller().state.capabilities != null,
    what: 'the transcript of $hostId seeded',
  );
  return (
    container: g.container,
    feed: g.feed,
    source: g.source,
    host: hostId,
    controller: controller,
  );
}

/// Whether [state]'s transcript has a row containing [text].
bool _shows(LaneState state, String text) =>
    state.rows.any((r) => r.text?.contains(text) ?? false);

/// Let [time] pass, pumping.
Future<void> _wait(WidgetTester tester, Duration time) async {
  final until = DateTime.now().add(time);
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ---------------------------------------------------------------------------
// settings (CM6)
// ---------------------------------------------------------------------------

/// The permodel session's models, in craze's order on grok-4.6.
const _permodelModels = [
  'grok-4.6',
  'composer-2.5',
  'claude-opus-5',
  'glm-5.2',
];

/// A tall view, so the whole settings sheet lays out with every row on
/// screen.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// **A craze session running craze's permodel cursor**, its transcript on
/// screen and seeded with its settings — created as `cursor` (`[agents]`
/// makes cursor ready; grok stays the default, and the config is put back at
/// once). Answers the graph, the session, its agent's record and its set gate.
Future<
  ({
    ProviderContainer container,
    MachineFeed feed,
    String host,
    LaneController Function() controller,
    String calls,
    CrazeSetGate gate,
  })
>
_permodel(
  WidgetTester tester,
  CrazeRig rig, {
  _RecordingSource? recording,
}) async {
  final calls = '${rig.root}/permodel-calls';
  final gate = CrazeSetGate('${rig.root}/set-gate');
  addTearDown(gate.open);
  final g = await _feedGraph(tester, rig, recording: recording);
  rig.setAgents({
    'grok': rig.grokEcho,
    'cursor': rig.permodelAgent(calls: calls, gate: gate.path),
  });
  final BridgeLaneCreated created;
  try {
    created = await g.feed.crazeCreateSession(
      BridgeLaneCreateRequest(
        cwd: _mkdir('${rig.root}/w-settings'),
        provider: 'cursor',
        requestId: crazeNewRequestId(),
      ),
    );
  } finally {
    rig.setGrokAgent(rig.grokEcho);
  }
  final host = created.session.id;
  await _showLane(tester, g.container, host);
  LaneController controller() => g.container.read(
    laneControllerProvider((
      machine: _local.name,
      kind: crazeLaneKind,
      slug: host,
    )),
  );
  await _until(
    tester,
    () =>
        controller().isOpen &&
        (controller().state.capabilities?.settings ?? false) &&
        controller().state.settings?.model == 'grok-4.6' &&
        find.byKey(const ValueKey('lane-settings-chip')).evaluate().isNotEmpty,
    what: 'the permodel session\'s settings',
  );
  return (
    container: g.container,
    feed: g.feed,
    host: host,
    controller: controller,
    calls: calls,
    gate: gate,
  );
}

/// The transcript header's settings chip, as it reads.
String _chip() =>
    (find
                .descendant(
                  of: find.byKey(const ValueKey('lane-settings-chip')),
                  matching: find.byType(Text),
                )
                .evaluate()
                .single
                .widget
            as Text)
        .data!;

/// Tap the chip and wait for the sheet.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('lane-settings-chip')));
  await _until(
    tester,
    () => find.byKey(const ValueKey('lane-settings')).evaluate().isNotEmpty,
    what: 'the settings sheet',
  );
}

/// The sheet's rows, by key (`<kind>:<id>`), in the order drawn.
List<String> _sheetRows() => find
    .byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          RegExp(r'^lane-setting-[a-z]+:[a-z_]+$').hasMatch(k.value);
    })
    .evaluate()
    .map(
      (e) => (e.widget.key! as ValueKey<String>).value.substring(
        'lane-setting-'.length,
      ),
    )
    .toList();

/// [row]'s values, by id, in the order drawn.
List<String> _values(String row) {
  final prefix = 'lane-setting-$row-';
  return find
      .byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith(prefix);
      })
      .evaluate()
      .map(
        (e) =>
            (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
      )
      .toList();
}

/// The value [row] SHOWS as current — the one its own semantics say is
/// selected — or null.
String? _shown(WidgetTester tester, String row) {
  for (final v in _values(row)) {
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(ValueKey('lane-setting-$row-$v')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    if (semantics.properties.selected ?? false) return v;
  }
  return null;
}

/// Whether [row] is drawn as a list (its current value checked) rather than
/// a segmented control.
bool _isList(WidgetTester tester, String row) => find
    .descendant(
      of: find.byKey(ValueKey('lane-setting-$row')),
      matching: find.byIcon(Icons.check),
    )
    .evaluate()
    .isNotEmpty;

/// The mark [row] shows inline, or null.
String? _markOf(String row) {
  final mark = find.byKey(ValueKey('lane-setting-mark-$row')).evaluate();
  return mark.isEmpty ? null : (mark.single.widget as Text).data;
}

/// Every row that shows a mark.
List<String> _sheetMarks() => [
  for (final row in _sheetRows())
    if (_markOf(row) != null) row,
];

/// Press [value] on [row], as a person would.
Future<void> _pressSetting(
  WidgetTester tester,
  String row,
  String value,
) async {
  final target = find.byKey(ValueKey('lane-setting-$row-$value'));
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 30));
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 30));
}
