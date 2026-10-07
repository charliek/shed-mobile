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
//   comes back live through its replacement (a send lands after); and no lane
//   is ever opened through a source that has not seeded.
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
  CrazeSourceOpen? openCrazeSource,
  CrazeSourceNudges? crazeNudges,
}) => MachineFeed(
  machine: _local,
  identities: const [],
  hostKeys: HostKeyStore(),
  entitlements: RoostBootstrapEntitlements(),
  openTunnel: rig.tunnelOpen,
  openCrazeSource: openCrazeSource,
  crazeNudges: crazeNudges,
);

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
