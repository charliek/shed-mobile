//! The app-scoped Rust→Dart stream registry shared by the mint inversion and the
//! credential events.
//!
//! Deliberately OUTSIDE `crate::api`: `flutter_rust_bridge.yaml` points the
//! codegen at `rust_input: crate::api`, and a generic type living there makes it
//! emit opaque glue for the type PARAMETER (`RustAutoOpaqueInner<T>`), which does
//! not compile. Shared infrastructure with generics belongs on this side of that
//! line; only concrete, marshallable API types belong on the other.

use std::sync::atomic::{AtomicU64, Ordering};

/// Where a registry sends: the live Dart `StreamSink` in production, a capturing
/// fake in the unit tests.
///
/// The indirection exists because `flutter_rust_bridge::StreamSink` can only be
/// built by the generated Dart-facing glue — a `cargo test` process cannot make
/// one. Behind this trait the tests drive the REAL registry (its locking, its
/// generations, its shutdown ordering) instead of a re-implementation of it,
/// which is the only way the race semantics below are actually covered.
pub(crate) trait Emitter<T>: Send + Sync {
    fn emit(&self, value: T) -> Result<(), ()>;
}

impl<T: crate::frb_generated::SseEncode + Send + Sync> Emitter<T>
    for crate::frb_generated::StreamSink<T>
{
    fn emit(&self, value: T) -> Result<(), ()> {
        self.add(value).map_err(|_| ())
    }
}

/// Why an emit found no listener. Both are fail-fast: the caller must NOT park
/// waiting for an answer that can never come.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EmitError {
    /// No sink is registered — either Dart has not listened yet
    /// (listener-before-client violated) or it has shut down.
    NoSink,
    /// A sink is registered but its Dart stream is closed.
    Closed,
}

/// One registration: the sink, the shutdown signal that ends its parked FRB
/// stream function, and the generation that ties them together.
///
/// The three live in ONE struct behind ONE lock deliberately. They used to sit
/// in two independently-locked cells, which admitted two real races: a
/// `shutdown` interleaving a registration could fire generation A's sender while
/// generation B's sink stayed installed (parked forever after Dart cancelled),
/// and two concurrent registrations could leave B's sink paired with A's sender.
/// A single slot makes "install", "observe and invalidate", and "release if I
/// still own it" indivisible.
struct SinkSlot<T> {
    generation: u64,
    emitter: std::sync::Arc<dyn Emitter<T>>,
    shutdown: tokio::sync::oneshot::Sender<()>,
}

/// The app-scoped registration for one Rust→Dart stream (the mint inversion, the
/// credential events). At most one listener exists per stream for the app's
/// lifetime; requests are routed inside the payload, not by having many sinks.
pub(crate) struct SinkRegistry<T> {
    slot: std::sync::Mutex<Option<SinkSlot<T>>>,
    generation: AtomicU64,
}

impl<T> SinkRegistry<T> {
    pub(crate) const fn new() -> Self {
        Self {
            slot: std::sync::Mutex::new(None),
            generation: AtomicU64::new(0),
        }
    }

    /// Install `emitter`, superseding any prior registration.
    ///
    /// Returns the new generation and the receiver the FRB stream function parks
    /// on. `on_evict` runs UNDER the slot lock (the mint registry drains its
    /// parked requests there) so nothing can slip between "the old sink is gone"
    /// and "the old sink's work is resolved". The evicted sender is fired after
    /// the lock is released — waking that task is not this task's critical
    /// section.
    ///
    /// A registration after a shutdown supersedes cleanly: it takes a fresh
    /// generation and installs, so an app that re-listens (hot restart, a new
    /// `ProviderContainer`) works with no special case.
    pub(crate) fn install(
        &self,
        emitter: std::sync::Arc<dyn Emitter<T>>,
        on_evict: impl FnOnce(),
    ) -> (u64, tokio::sync::oneshot::Receiver<()>) {
        let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let (tx, rx) = tokio::sync::oneshot::channel();
        let prior = {
            let mut slot = self.lock();
            let prior = slot.take();
            *slot = Some(SinkSlot {
                generation,
                emitter,
                shutdown: tx,
            });
            on_evict();
            prior
        };
        if let Some(p) = prior {
            let _ = p.shutdown.send(());
        }
        (generation, rx)
    }

    /// Remove the registration and end its stream function. Idempotent.
    ///
    /// `while_locked` runs under the SAME lock that removed the slot, which is
    /// what closes the "resolved, then a new request parks, then the sender
    /// fires" hole: from the instant the slot is taken, every [`Self::emit`]
    /// fails fast, so a request that parks during a shutdown discovers it has no
    /// listener immediately instead of waiting out its timeout.
    pub(crate) fn shutdown(&self, while_locked: impl FnOnce()) {
        let slot = {
            let mut slot = self.lock();
            let taken = slot.take();
            while_locked();
            taken
        };
        if let Some(s) = slot {
            let _ = s.shutdown.send(());
        }
    }

    /// Clear the slot IFF `generation` still owns it — what a woken stream
    /// function calls on its way out, so a sink installed while it was parked is
    /// never clobbered.
    pub(crate) fn release(&self, generation: u64) {
        let mut slot = self.lock();
        if slot.as_ref().map(|s| s.generation) == Some(generation) {
            *slot = None;
        }
    }

    /// Send one value to Dart, or fail fast.
    ///
    /// The emitter is CLONED out and the lock released before it is called, so no
    /// foreign code ever runs under this registry's lock. That matters because
    /// the natural thing for a listener to do — a Dart `onDispose` that reaches
    /// back into `shutdownMintSink`, a handler that re-registers — would
    /// otherwise re-enter a non-reentrant mutex and hang the app.
    ///
    /// The cost is a benign race: a shutdown landing between the clone and the
    /// call delivers one last value to a listener that is going away. Harmless in
    /// both directions — a closed Dart port drops it, and any request it was
    /// answering has already been resolved by that same shutdown's drain.
    pub(crate) fn emit(&self, value: T) -> Result<(), EmitError> {
        let emitter = self.lock().as_ref().map(|s| s.emitter.clone());
        let Some(emitter) = emitter else {
            return Err(EmitError::NoSink);
        };
        emitter.emit(value).map_err(|()| EmitError::Closed)
    }

    /// Poisoning is recovered rather than propagated: a panic inside a foreign
    /// handler must not take the app's only mint channel down with it.
    fn lock(&self) -> std::sync::MutexGuard<'_, Option<SinkSlot<T>>> {
        self.slot.lock().unwrap_or_else(|e| e.into_inner())
    }
}
