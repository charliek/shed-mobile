//! Each cloud shed's extend while one is in flight or its outcome is unknown
//! (plan 041), so the phone never moves a lease twice.
//!
//! The phone does not link `shed-app`; this mirrors the rules of its
//! `extend.rs`, kept small. An extend whose every send ended with no answer (or
//! a 5xx) may or may not have moved the lease. It is never sent again: it is
//! settled by observation, by what the shed's later listings show, and while it
//! is unsettled every extend of that shed is refused here, unsent. A record
//! belongs to one incarnation of a shed (its server, name and creation time), so
//! a shed created again under the name never inherits it.
//!
//! The rules ([`settled`]):
//! * applied: the lease's end is at least its end before the extend plus the
//!   hours;
//! * not applied: the end is still exactly the old end, at least
//!   [`EXTEND_SETTLE_MS`] after the outcome was recorded (a lease moved by fewer
//!   hours proves nothing about this extend, so that record waits for the age
//!   limit);
//! * the shed is gone from its server's listing, or is another incarnation;
//! * [`EXTEND_UNKNOWN_MAX_MS`] after the outcome was recorded, whatever the
//!   listing says.
//!
//! Only a listing that succeeded settles anything, and only the outcomes
//! recorded before it was sent ([`ExtendBook::listing_mark`]): one sent earlier
//! may predate the extend. A listing never touches a shed whose extend has its
//! turn: that extend's own read of the shed (taken after the turn) settles what
//! it holds ([`ExtendBook::admit`]).

use std::collections::BTreeMap;
use std::future::Future;
use std::sync::Mutex;

use shed_core::http::{ApiFailure, ExtendOutcome};
use shed_core::models::{refusal_words, Shed, MAX_EXTEND_HOURS};
use shed_lane::time::rfc3339_unix_ms;

use crate::api::dto::{BridgeExtendOutcome, BridgeShed};

/// How long after an unknown outcome a lease whose end is still exactly its old
/// end means the extend was not applied: two of the server's sweeps (60 s each)
/// and a margin.
pub(crate) const EXTEND_SETTLE_MS: i64 = 150_000;

/// The longest an unknown outcome is kept: the account service keeps an
/// extend's answer this long, and nothing after it says more.
pub(crate) const EXTEND_UNKNOWN_MAX_MS: i64 = 24 * 60 * 60 * 1000;

/// The words of an extend whose outcome is not known.
pub(crate) const EXTEND_UNKNOWN_WORDS: &str =
    "not known whether it was applied; Extend stays unavailable until that is known";

/// The words of an extend refused here, unsent.
pub(crate) const EXTEND_PENDING_WORDS: &str =
    "an earlier extend's outcome is not known yet; Extend stays unavailable until it is";

/// The process-wide book: one per app, keyed by (server, shed), so it outlives a
/// `BridgeClient` rebuilt for the same server.
pub(crate) static EXTENDS: ExtendBook = ExtendBook::new();

/// The time now in unix milliseconds.
pub(crate) fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
}

/// A shed's incarnation: its creation time as its server sent it ("" when none).
fn incarnation(shed: &Shed) -> String {
    shed.created_at.clone().unwrap_or_default()
}

/// A shed's lease end in unix milliseconds, when known.
fn lease_end(shed: &Shed) -> Option<i64> {
    rfc3339_unix_ms(&shed.cloud.as_ref()?.lease.as_ref()?.expires_at)
}

/// An extend whose outcome is not known.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct UnknownExtend {
    incarnation: String,
    hours: u32,
    /// The lease's end before it was sent (unix ms), when known.
    before: Option<i64>,
    /// When its outcome was found unknown (unix ms).
    at: i64,
}

/// Whether `u` is settled by `observed` (the shed as a listing has it now;
/// `None`: the listing has no shed of that name) at `now`.
fn settled(u: &UnknownExtend, observed: Option<&Shed>, now: i64) -> bool {
    if now - u.at >= EXTEND_UNKNOWN_MAX_MS {
        return true;
    }
    let Some(shed) = observed else {
        return true; // gone
    };
    if incarnation(shed) != u.incarnation {
        return true; // another shed under the name
    }
    let (Some(before), Some(end)) = (u.before, lease_end(shed)) else {
        return false;
    };
    let applied = end >= before + i64::from(u.hours) * 3_600_000;
    let not_applied = end == before && now - u.at >= EXTEND_SETTLE_MS;
    applied || not_applied
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Recorded {
    u: UnknownExtend,
    /// Its place in the order outcomes were recorded in, compared with a
    /// listing's mark.
    seq: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Slot {
    /// An extend has the shed's turn (reading the shed, or sending). `held` is an
    /// earlier unknown outcome, kept for that read to settle.
    InFlight {
        held: Option<Recorded>,
    },
    Unknown(Recorded),
}

struct Slots {
    by_shed: BTreeMap<(String, String), Slot>,
    /// How many unknown outcomes have been recorded: the last one's `seq`.
    recorded: u64,
}

/// Each shed's extend in flight or with an unknown outcome, by (server, shed).
pub(crate) struct ExtendBook {
    slots: Mutex<Slots>,
}

fn key(server: &str, name: &str) -> (String, String) {
    (server.to_string(), name.to_string())
}

impl ExtendBook {
    pub(crate) const fn new() -> Self {
        ExtendBook {
            slots: Mutex::new(Slots {
                by_shed: BTreeMap::new(),
                recorded: 0,
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Slots> {
        self.slots.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Take the shed's turn before it is read: `false` when an extend of it is
    /// in flight. An earlier unknown outcome is held, for that read to settle.
    fn reserve(&self, server: &str, name: &str) -> bool {
        let mut slots = self.lock();
        let k = key(server, name);
        let held = match slots.by_shed.remove(&k) {
            Some(s @ Slot::InFlight { .. }) => {
                slots.by_shed.insert(k, s);
                return false;
            }
            Some(Slot::Unknown(r)) => Some(r),
            None => None,
        };
        slots.by_shed.insert(k, Slot::InFlight { held });
        true
    }

    /// Let the reserved extend be sent, `observed` being the shed as read after
    /// [`Self::reserve`]: a held unknown outcome is settled by it first, or put
    /// back and the extend refused (`false`).
    fn admit(&self, server: &str, name: &str, observed: &Shed, now: i64) -> bool {
        let mut slots = self.lock();
        let k = key(server, name);
        match slots.by_shed.remove(&k) {
            Some(Slot::InFlight { held: None }) => {}
            Some(Slot::InFlight { held: Some(r) }) => {
                if !settled(&r.u, Some(observed), now) {
                    slots.by_shed.insert(k, Slot::Unknown(r));
                    return false;
                }
            }
            other => {
                if let Some(s) = other {
                    slots.by_shed.insert(k, s);
                }
                return false;
            }
        }
        slots.by_shed.insert(k, Slot::InFlight { held: None });
        true
    }

    /// Give back a turn when nothing was sent: a held unknown outcome is put
    /// back, unsettled (`true`).
    fn release(&self, server: &str, name: &str) -> bool {
        let mut slots = self.lock();
        let k = key(server, name);
        match slots.by_shed.remove(&k) {
            Some(Slot::InFlight { held: Some(r) }) => {
                slots.by_shed.insert(k, Slot::Unknown(r));
                true
            }
            Some(Slot::InFlight { held: None }) | None => false,
            Some(s) => {
                slots.by_shed.insert(k, s);
                false
            }
        }
    }

    /// End the admitted extend: `Some` records its unknown outcome, `None` (an
    /// answer) frees the slot.
    fn finish(&self, server: &str, name: &str, unknown: Option<UnknownExtend>) {
        let mut slots = self.lock();
        let k = key(server, name);
        if !matches!(slots.by_shed.get(&k), Some(Slot::InFlight { held: None })) {
            return;
        }
        match unknown {
            Some(u) => {
                slots.recorded += 1;
                let seq = slots.recorded;
                slots.by_shed.insert(k, Slot::Unknown(Recorded { u, seq }));
            }
            None => {
                slots.by_shed.remove(&k);
            }
        }
    }

    /// The mark to take before a listing is sent and hand to [`Self::observe`].
    pub(crate) fn listing_mark(&self) -> u64 {
        self.lock().recorded
    }

    /// Settle what `server`'s listing (`rows`, every shed it listed), sent after
    /// `mark` was taken and at `now` (the time it was SENT, [`listing`]), shows.
    /// Only for a listing that succeeded.
    pub(crate) fn observe(&self, server: &str, rows: &[Shed], mark: u64, now: i64) {
        self.lock().by_shed.retain(|(s, name), slot| match slot {
            Slot::Unknown(r) if s == server && r.seq <= mark => {
                !settled(&r.u, rows.iter().find(|row| &row.name == name), now)
            }
            _ => true,
        });
    }

    /// The hours of the shed's extend whose outcome is not known, if any.
    pub(crate) fn unknown_hours(&self, server: &str, name: &str) -> Option<u32> {
        match self.lock().by_shed.get(&key(server, name))? {
            Slot::Unknown(r) | Slot::InFlight { held: Some(r) } => Some(r.u.hours),
            Slot::InFlight { held: None } => None,
        }
    }
}

/// The fixed words for a failed extend: the account service's words for its
/// refusals ([`refusal_words`]), else a line naming the code or the status,
/// never the server's message.
pub(crate) fn failure_words(e: &ApiFailure) -> String {
    if let Some(words) = refusal_words(&e.code, &e.reason) {
        return words.to_string();
    }
    match (e.code.as_str(), e.status) {
        ("", Some(status)) => format!("the extend failed (HTTP {status})"),
        ("", None) => "the extend could not be sent".to_string(),
        (code, _) => format!("the extend was refused ({code})"),
    }
}

fn refused(e: &ApiFailure) -> BridgeExtendOutcome {
    BridgeExtendOutcome::Refused {
        code: e.code.clone(),
        reason: e.reason.clone(),
        status: e.status,
        words: failure_words(e),
    }
}

fn pending() -> BridgeExtendOutcome {
    BridgeExtendOutcome::Pending {
        words: EXTEND_PENDING_WORDS.to_string(),
    }
}

/// The shed's turn while an extend has it: given back if the extend ends before
/// anything is sent, recorded unknown if it ends while sending (a panic).
struct Turn<'a> {
    book: &'a ExtendBook,
    server: &'a str,
    name: &'a str,
    now: &'a (dyn Fn() -> i64 + Send + Sync),
    sending: Option<UnknownExtend>,
    done: bool,
}

impl Drop for Turn<'_> {
    fn drop(&mut self) {
        if self.done {
            return;
        }
        match self.sending.take() {
            Some(u) => {
                let at = (self.now)();
                self.book
                    .finish(self.server, self.name, Some(UnknownExtend { at, ..u }));
            }
            None => {
                self.book.release(self.server, self.name);
            }
        }
    }
}

/// One extend of `name` on `server` by `hours`: take the shed's turn, `read` the
/// shed (its incarnation and lease end before the extend), then `send` it (one
/// request id, its own retries). An outcome that stays unknown is recorded and
/// refuses every later extend of the shed unsent until a listing settles it.
pub(crate) async fn extend<R, S>(
    book: &ExtendBook,
    server: &str,
    name: &str,
    hours: i64,
    now: &(dyn Fn() -> i64 + Send + Sync),
    read: R,
    send: impl FnOnce(u32) -> S,
) -> BridgeExtendOutcome
where
    R: Future<Output = Result<Shed, ApiFailure>>,
    S: Future<Output = ExtendOutcome>,
{
    let Some(hours) = u32::try_from(hours)
        .ok()
        .filter(|h| (1..=MAX_EXTEND_HOURS).contains(&i64::from(*h)))
    else {
        return BridgeExtendOutcome::Refused {
            code: "extend_bad_hours".to_string(),
            reason: String::new(),
            status: None,
            words: format!("hours is a whole number from 1 to {MAX_EXTEND_HOURS}"),
        };
    };
    if !book.reserve(server, name) {
        return pending();
    }
    let mut turn = Turn {
        book,
        server,
        name,
        now,
        sending: None,
        done: false,
    };
    let before = match read.await {
        Ok(shed) => shed,
        Err(e) => {
            turn.done = true;
            return if book.release(server, name) {
                pending()
            } else {
                refused(&e)
            };
        }
    };
    if !book.admit(server, name, &before, now()) {
        turn.done = true; // admit put the held outcome back
        return pending();
    }
    let unknown = UnknownExtend {
        incarnation: incarnation(&before),
        hours,
        before: lease_end(&before),
        at: 0,
    };
    turn.sending = Some(unknown.clone());
    let out = send(hours).await;
    turn.done = true;
    // shed-core says what is unknown: every send ended with no answer or a 5xx,
    // a later send's refusal that did not judge this request id, or a 2xx whose
    // shed could not be read (the lease moved, the answer is lost). Anything
    // else is definite: the shed it answered, or a refusal, including one made
    // before anything was sent (a credential the client could not get).
    let definite = !out.unresolved;
    if definite {
        book.finish(server, name, None);
        return match out.result {
            Ok(shed) => BridgeExtendOutcome::Extended { shed: shed.into() },
            Err(e) => refused(&e),
        };
    }
    book.finish(
        server,
        name,
        Some(UnknownExtend {
            at: now(),
            ..unknown
        }),
    );
    BridgeExtendOutcome::Unknown {
        hours,
        words: EXTEND_UNKNOWN_WORDS.to_string(),
    }
}

/// Run one listing of `server` (`list`) and settle what it shows (`rows`) of
/// the unknown outcomes. The mark and the time are both taken BEFORE it is
/// sent: the server may have sampled the lease as soon as the request arrived,
/// so the not-applied wait ([`EXTEND_SETTLE_MS`]) is measured to then, never to
/// when the reply came back. A listing that fails settles nothing.
pub(crate) async fn listing<T, E, F>(
    book: &ExtendBook,
    server: &str,
    now: &(dyn Fn() -> i64 + Send + Sync),
    list: F,
    rows: impl FnOnce(&T) -> Vec<Shed>,
) -> Result<T, E>
where
    F: Future<Output = Result<T, E>>,
{
    let mark = book.listing_mark();
    let sent_at = now();
    let out = list.await?;
    book.observe(server, &rows(&out), mark, sent_at);
    Ok(out)
}

/// Stamp each listed shed with its extend whose outcome is not known.
pub(crate) fn stamp(book: &ExtendBook, server: &str, shed: &mut BridgeShed) {
    shed.extend_unknown_hours = book.unknown_hours(server, &shed.name);
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};
    use std::sync::Arc;

    const H: i64 = 3_600_000;
    /// 2026-11-26T09:00:00Z in unix ms.
    const T0: i64 = 1_795_683_600_000;

    fn iso(ms: i64) -> String {
        shed_lane::time::rfc3339_z(ms / 1000)
    }

    /// A cloud shed whose lease ends at `end` (unix ms), created at `created`.
    fn shed(name: &str, created: &str, end: i64) -> Shed {
        serde_json::from_value(json!({
            "name": name, "status": "running", "backend": "remote", "created_at": created,
            "cloud": {"lease": {
                "expires_at": iso(end), "max_expires_at": iso(end + 100 * H),
                "extendable": true, "presets_h": [6, 12],
            }},
        }))
        .unwrap()
    }

    fn unknown(before: i64, hours: u32, at: i64) -> UnknownExtend {
        UnknownExtend {
            incarnation: "c1".into(),
            hours,
            before: Some(before),
            at,
        }
    }

    fn outcome(result: Result<Shed, ApiFailure>, unresolved: bool) -> ExtendOutcome {
        ExtendOutcome { result, unresolved }
    }

    fn failure(status: Option<u16>, code: &str, reason: &str) -> ApiFailure {
        ApiFailure {
            status,
            code: code.into(),
            message: "SERVER TEXT".into(),
            reason: reason.into(),
        }
    }

    /// A clock the test moves.
    struct Clock(Arc<AtomicI64>);
    impl Clock {
        fn new(at: i64) -> Self {
            Clock(Arc::new(AtomicI64::new(at)))
        }
        fn set(&self, at: i64) {
            self.0.store(at, Ordering::SeqCst);
        }
        fn f(&self) -> impl Fn() -> i64 + Send + Sync {
            let a = self.0.clone();
            move || a.load(Ordering::SeqCst)
        }
    }

    // ---- the settle rules ----

    #[test]
    fn applied_when_the_end_reached_the_old_end_plus_the_hours() {
        let u = unknown(T0, 6, T0);
        assert!(settled(&u, Some(&shed("w", "c1", T0 + 6 * H)), T0 + 1));
        assert!(settled(&u, Some(&shed("w", "c1", T0 + 7 * H)), T0 + 1));
        // Moved by fewer hours: proves nothing, at any age short of the limit.
        assert!(!settled(&u, Some(&shed("w", "c1", T0 + 5 * H)), T0 + 1));
        assert!(!settled(
            &u,
            Some(&shed("w", "c1", T0 + 5 * H)),
            T0 + EXTEND_UNKNOWN_MAX_MS - 1
        ));
    }

    #[test]
    fn not_applied_only_when_unmoved_and_settle_time_passed() {
        let u = unknown(T0, 6, T0);
        let same = shed("w", "c1", T0);
        assert!(!settled(&u, Some(&same), T0 + EXTEND_SETTLE_MS - 1));
        assert!(settled(&u, Some(&same), T0 + EXTEND_SETTLE_MS));
    }

    #[test]
    fn gone_replaced_or_too_old_settles() {
        let u = unknown(T0, 6, T0);
        assert!(settled(&u, None, T0 + 1), "gone");
        assert!(
            settled(&u, Some(&shed("w", "c2", T0)), T0 + 1),
            "another incarnation"
        );
        let mut no_lease = shed("w", "c1", T0);
        no_lease.cloud = None;
        assert!(!settled(&u, Some(&no_lease), T0 + 1), "lease unknown");
        assert!(
            settled(&u, Some(&no_lease), T0 + EXTEND_UNKNOWN_MAX_MS),
            "24 h"
        );
    }

    // ---- the book ----

    fn record(book: &ExtendBook, u: UnknownExtend) {
        assert!(book.reserve("s", "w"));
        assert!(book.admit("s", "w", &shed("w", "c1", T0), u.at));
        book.finish("s", "w", Some(u));
    }

    #[test]
    fn a_listing_sent_before_the_record_settles_nothing() {
        let book = ExtendBook::new();
        let early = book.listing_mark();
        record(&book, unknown(T0, 6, T0));
        book.observe("s", &[], early, T0 + 1);
        assert_eq!(book.unknown_hours("s", "w"), Some(6), "an earlier listing");
        book.observe("other", &[], book.listing_mark(), T0 + 1);
        assert_eq!(book.unknown_hours("s", "w"), Some(6), "another server");
        book.observe("s", &[shed("w", "c1", T0)], book.listing_mark(), T0 + 1);
        assert_eq!(book.unknown_hours("s", "w"), Some(6), "unmoved, too soon");
        book.observe("s", &[], book.listing_mark(), T0 + 1);
        assert_eq!(book.unknown_hours("s", "w"), None, "gone");
    }

    #[test]
    fn a_listing_settles_applied_and_not_applied() {
        let book = ExtendBook::new();
        record(&book, unknown(T0, 6, T0));
        book.observe(
            "s",
            &[shed("w", "c1", T0 + 6 * H)],
            book.listing_mark(),
            T0 + 1,
        );
        assert_eq!(book.unknown_hours("s", "w"), None, "applied");

        record(&book, unknown(T0, 6, T0));
        book.observe(
            "s",
            &[shed("w", "c1", T0)],
            book.listing_mark(),
            T0 + EXTEND_SETTLE_MS,
        );
        assert_eq!(book.unknown_hours("s", "w"), None, "not applied");
    }

    /// The not-applied wait is measured to when the listing was sent: one sent
    /// before the 150 s point that returns after it does not settle the record
    /// as not applied; one sent after it does.
    #[test]
    fn a_listing_is_timed_when_it_is_sent_not_when_it_returns() {
        let book = ExtendBook::new();
        record(&book, unknown(T0, 6, T0));
        let clock = Clock::new(T0 + EXTEND_SETTLE_MS - 1000);
        let now = clock.f();
        let unmoved = || vec![shed("w", "c1", T0)];
        let slow = run(listing(
            &book,
            "s",
            &now,
            async {
                // The reply arrives after the 150 s point.
                clock.set(T0 + EXTEND_SETTLE_MS + 5000);
                Ok::<_, ()>(unmoved())
            },
            |rows| rows.clone(),
        ));
        assert!(slow.is_ok());
        assert_eq!(book.unknown_hours("s", "w"), Some(6), "sent too soon");

        // A listing that fails settles nothing.
        let failed = run(listing(
            &book,
            "s",
            &now,
            async { Err::<Vec<Shed>, _>("down") },
            |rows| rows.clone(),
        ));
        assert_eq!(failed, Err("down"));
        assert_eq!(book.unknown_hours("s", "w"), Some(6));

        let late = run(listing(
            &book,
            "s",
            &now,
            async { Ok::<_, ()>(unmoved()) },
            |rows| rows.clone(),
        ));
        assert!(late.is_ok());
        assert_eq!(book.unknown_hours("s", "w"), None, "sent after it");
    }

    #[test]
    fn a_listing_leaves_a_shed_whose_extend_has_its_turn() {
        let book = ExtendBook::new();
        record(&book, unknown(T0, 6, T0));
        assert!(book.reserve("s", "w"), "holds the unknown outcome");
        assert!(!book.reserve("s", "w"), "one turn at a time");
        book.observe("s", &[], book.listing_mark(), T0 + 1);
        assert_eq!(book.unknown_hours("s", "w"), Some(6), "still held");
        assert!(book.release("s", "w"), "put back");
        assert_eq!(book.unknown_hours("s", "w"), Some(6));
    }

    // ---- the flow ----

    fn run<F: Future>(f: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(f)
    }

    #[test]
    fn an_unknown_outcome_refuses_the_next_extend_unsent_until_settled() {
        let book = ExtendBook::new();
        let clock = Clock::new(T0);
        let now = clock.f();
        let sends = AtomicUsize::new(0);
        let extend_by = |hours: i64, read: Shed, result: ExtendOutcome| {
            let sends = &sends;
            extend(
                &book,
                "s",
                "w",
                hours,
                &now,
                async move { Ok(read) },
                move |_h| {
                    sends.fetch_add(1, Ordering::SeqCst);
                    async move { result }
                },
            )
        };
        let lost = || outcome(Err(failure(None, "", "")), true);

        // Every send lost: unknown, recorded.
        let out = run(extend_by(6, shed("w", "c1", T0), lost()));
        assert_eq!(
            out,
            BridgeExtendOutcome::Unknown {
                hours: 6,
                words: EXTEND_UNKNOWN_WORDS.into()
            }
        );
        assert_eq!(book.unknown_hours("s", "w"), Some(6));

        // The next extend reads the shed unmoved, too soon: refused, never sent.
        clock.set(T0 + 1000);
        let out = run(extend_by(6, shed("w", "c1", T0), lost()));
        assert!(matches!(out, BridgeExtendOutcome::Pending { .. }));
        assert_eq!(sends.load(Ordering::SeqCst), 1);
        assert_eq!(book.unknown_hours("s", "w"), Some(6));

        // The lease is seen moved by the hours: the outcome settles as applied,
        // and this extend goes through.
        let moved = shed("w", "c1", T0 + 6 * H);
        let answer = shed("w", "c1", T0 + 12 * H);
        let out = run(extend_by(6, moved, outcome(Ok(answer), false)));
        assert!(matches!(out, BridgeExtendOutcome::Extended { .. }));
        assert_eq!(sends.load(Ordering::SeqCst), 2);
        assert_eq!(book.unknown_hours("s", "w"), None);
    }

    #[test]
    fn refusals_show_fixed_words_never_the_message() {
        let book = ExtendBook::new();
        let now = || T0;
        let go = |e: ApiFailure| {
            run(extend(
                &book,
                "s",
                "w",
                6,
                &now,
                async { Ok(shed("w", "c1", T0)) },
                move |_| async move { outcome(Err(e), false) },
            ))
        };
        let words = |o: BridgeExtendOutcome| match o {
            BridgeExtendOutcome::Refused { words, .. } => words,
            other => panic!("{other:?}"),
        };
        assert_eq!(
            words(go(failure(Some(409), "LEASE_AT_CAP", ""))),
            refusal_words("LEASE_AT_CAP", "").unwrap()
        );
        assert_eq!(
            words(go(failure(Some(409), "SOMETHING_NEW", ""))),
            "the extend was refused (SOMETHING_NEW)"
        );
        assert_eq!(
            words(go(failure(Some(400), "", ""))),
            "the extend failed (HTTP 400)"
        );
        assert_eq!(
            book.unknown_hours("s", "w"),
            None,
            "a refusal frees the turn"
        );
    }

    /// What is unknown is what shed-core says is (`unresolved`): an unreadable
    /// 2xx, a lost reply, a 5xx on every send. Each is recorded and refuses the
    /// next extend unsent, so the hours are never added twice. A failure with
    /// `unresolved == false` is definite, even with no status (a credential
    /// refused before anything was sent): the turn is given back and the next
    /// extend is sent.
    #[test]
    fn unknown_is_exactly_what_shed_core_marks_unresolved() {
        let cases = [
            (failure(Some(200), "", "decode error: body too large"), true),
            (failure(Some(503), "", ""), true),
            (failure(None, "", "transport error"), true),
            (failure(None, "", "no credential: mint refused"), false),
        ];
        for (i, (e, unresolved)) in cases.into_iter().enumerate() {
            let book = ExtendBook::new();
            let now = || T0;
            let sends = AtomicUsize::new(0);
            let go = |e: Option<ApiFailure>| {
                let sends = &sends;
                run(extend(
                    &book,
                    "s",
                    "w",
                    6,
                    &now,
                    async { Ok(shed("w", "c1", T0)) },
                    move |_| {
                        sends.fetch_add(1, Ordering::SeqCst);
                        async move {
                            match e {
                                Some(e) => outcome(Err(e), unresolved),
                                None => outcome(Ok(shed("w", "c1", T0 + 6 * H)), false),
                            }
                        }
                    },
                ))
            };
            let out = go(Some(e));
            if unresolved {
                assert!(
                    matches!(out, BridgeExtendOutcome::Unknown { hours: 6, .. }),
                    "case {i}: {out:?}"
                );
                assert_eq!(book.unknown_hours("s", "w"), Some(6), "case {i}");
                assert!(
                    matches!(go(None), BridgeExtendOutcome::Pending { .. }),
                    "case {i}: the next extend is refused unsent"
                );
                assert_eq!(sends.load(Ordering::SeqCst), 1, "case {i}: sent once");
            } else {
                assert!(
                    matches!(&out, BridgeExtendOutcome::Refused { words, .. }
                        if words == "the extend could not be sent"),
                    "case {i}: {out:?}"
                );
                assert_eq!(book.unknown_hours("s", "w"), None, "case {i}");
                assert!(
                    matches!(go(None), BridgeExtendOutcome::Extended { .. }),
                    "case {i}: the turn was given back"
                );
                assert_eq!(sends.load(Ordering::SeqCst), 2, "case {i}");
            }
        }
    }

    #[test]
    fn bad_hours_are_unsent() {
        let book = ExtendBook::new();
        let now = || T0;
        for bad in [0, -1, MAX_EXTEND_HOURS + 1] {
            let out = run(extend(
                &book,
                "s",
                "x",
                bad,
                &now,
                async { Ok(shed("x", "c1", T0)) },
                |_| async { panic!("never sent") },
            ));
            assert!(
                matches!(&out, BridgeExtendOutcome::Refused { code, .. } if code == "extend_bad_hours")
            );
        }
    }

    #[test]
    fn a_failed_read_sends_nothing_and_keeps_a_held_outcome() {
        let book = ExtendBook::new();
        record(&book, unknown(T0, 6, T0));
        let now = || T0 + 1;
        let out = run(extend(
            &book,
            "s",
            "w",
            6,
            &now,
            async { Err(failure(Some(404), "NOT_FOUND", "")) },
            |_| async { panic!("never sent") },
        ));
        assert!(matches!(out, BridgeExtendOutcome::Pending { .. }));
        assert_eq!(book.unknown_hours("s", "w"), Some(6));

        // With nothing held, the read's failure is the answer, in fixed words.
        let out = run(extend(
            &book,
            "s",
            "y",
            6,
            &now,
            async { Err(failure(Some(404), "NOT_FOUND", "")) },
            |_| async { panic!("never sent") },
        ));
        assert!(
            matches!(&out, BridgeExtendOutcome::Refused { words, .. } if words == "the extend was refused (NOT_FOUND)")
        );
    }
}
