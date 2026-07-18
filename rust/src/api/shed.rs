//! FRB de-risking spike: a tiny bridged surface that forces the shed client
//! core to actually link into the Flutter native lib.
//!
//! Each call below reaches a DIFFERENT corner of `shed-core` / `shed-app` so
//! that neither dead-code elimination nor lazy feature resolution can quietly
//! drop the heavy transitive deps (tokio / reqwest / rustls-ring). If these
//! symbols are present in the built `.so`/`.dylib`, the linkage risk is retired.

/// Async round-trip through `shed_core::ping` (exercises the async bridge path
/// + pulls in tokio), plus two synchronous pure-Rust probes:
///   * `shed_core::token::name_jitter` — pure, deterministic-shape token helper.
///   * `shed_core::http::Client::new`  — CONSTRUCTS a reqwest client, which is
///     what forces reqwest + rustls (ring) to link. We use a bogus https URL so
///     no network I/O happens; we only care that the client builds.
pub async fn shed_core_probe(echo: String) -> String {
    let pong = shed_core::ping(echo).await;

    let jitter = shed_core::token::name_jitter("test", 300_000);

    let client_built = shed_core::http::Client::new(
        "https://example.invalid".to_string(),
        "frb-spike".to_string(),
        String::new(),
        None,
        None,
    )
    .is_ok();

    format!("{pong} | name_jitter(test,300000)={jitter} | reqwest_client_built={client_built}")
}

/// Proves `shed-app` (default features) also links — constructs an in-memory
/// `AuditStore` (a display-free app-logic type) and reports its empty tail.
/// This is the "shed-app is reachable, no `rc` feature needed" check.
pub fn shed_app_probe() -> String {
    let store = shed_app::AuditStore::new("/tmp/frb-spike-audit.log");
    let tail = store.recent(0).len();
    format!("shed_app::AuditStore linked (tail={tail})")
}
