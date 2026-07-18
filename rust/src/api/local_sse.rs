//! A minimal in-process HTTP/SSE server for the hermetic bridge proofs — the
//! same shape shed-core's own `rc_events`/`create_shed` tests use (a raw socket
//! writing a scripted response), spawned on the bridge runtime so a bridged
//! `Client` can hit it over real reqwest/rustls-free plaintext HTTP. Binds
//! `127.0.0.1:0`, serves each accepted connection the scripted response then
//! closes it (a clean EOF), looping so a reconnecting watcher is served again.
//!
//! **Honest leak accounting (Codex review #11):** each spawned server is owned by
//! a [`BridgeTestSse`] opaque handle that RETAINS its abort handle, counts itself
//! in [`ACTIVE_SSE_SERVERS`], and aborts + decrements on `stop()`/`Drop`. So the
//! zero-leak assertions cover these test servers too — the accept loops no longer
//! detach and run until process exit.

use std::sync::atomic::{AtomicBool, Ordering};

use flutter_rust_bridge::frb;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

use super::bridge_rt::{bridge_rt, ACTIVE_SSE_SERVERS};

/// The rc-events body the hermetic watcher test serves: the server preamble +
/// two rc events (the shape shed-core's own `rc_events` happy-path test uses).
const WATCHER_SSE: &str = ": ok\n\n\
event: activity.changed\n\
data: {\"shed\":\"proj\",\"slug\":\"cdx777\",\"activity\":\"working\",\"state\":\"ready\"}\n\n\
event: session.updated\n\
data: {\"shed\":\"proj\",\"slug\":\"cdx777\",\"session\":{\"state\":\"ready\",\"activity\":\"idle\"}}\n\n";

/// The create body the hermetic create-stream test serves: two progress frames
/// then a complete.
const CREATE_SSE: &str = "event: progress\n\
data: {\"message\":\"building rootfs\"}\n\n\
event: progress\n\
data: {\"message\":\"booting vm\"}\n\n\
event: complete\n\
data: {\"name\":\"folio\",\"status\":\"running\"}\n\n";

/// A counted, stoppable hermetic test server (Codex review #11). Dart holds it,
/// reads its `base_url`, and stops it (or drops it) at the end of a test.
#[frb(opaque)]
pub struct BridgeTestSse {
    base_url: String,
    abort: tokio::task::AbortHandle,
    stopped: AtomicBool,
}

impl BridgeTestSse {
    /// The `http://127.0.0.1:<port>` an OPEN-mode `BridgeClient` is built against.
    #[frb(sync)]
    pub fn base_url(&self) -> String {
        self.base_url.clone()
    }

    /// Idempotent synchronous stop: abort the accept loop, decrement the counter.
    #[frb(sync)]
    pub fn stop(&self) {
        if !self.stopped.swap(true, Ordering::SeqCst) {
            self.abort.abort();
            ACTIVE_SSE_SERVERS.fetch_sub(1, Ordering::SeqCst);
        }
    }
}

impl Drop for BridgeTestSse {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Stand up the hermetic rc-events SSE server. Test-support only.
pub async fn spawn_watcher_test_sse() -> BridgeTestSse {
    spawn(Response::sse(WATCHER_SSE)).await
}

/// Stand up the hermetic create SSE server. Test-support only.
pub async fn spawn_create_test_sse() -> BridgeTestSse {
    spawn(Response::sse(CREATE_SSE)).await
}

/// Stand up a server that answers every request with a fixed HTTP `status` and a
/// tiny JSON body — for the create-stream one-shot-on-error proof (Codex #8).
/// Test-support only.
pub async fn spawn_status_test_sse(status: u16) -> BridgeTestSse {
    spawn(Response::status(status)).await
}

/// A scripted response the local server writes on each accepted connection.
enum Response {
    /// A `200 text/event-stream` header + these frames.
    Sse(&'static str),
    /// A bare `<status>` line + a tiny JSON body.
    Status(u16),
}

impl Response {
    fn sse(body: &'static str) -> Response {
        Response::Sse(body)
    }
    fn status(code: u16) -> Response {
        Response::Status(code)
    }
    fn bytes(&self) -> Vec<u8> {
        match self {
            Response::Sse(body) => {
                let mut v = b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n".to_vec();
                v.extend_from_slice(body.as_bytes());
                v
            }
            Response::Status(code) => format!(
                "HTTP/1.1 {code} STATUS\r\ncontent-type: application/json\r\nconnection: close\r\n\r\n{{\"error\":\"status {code}\"}}"
            )
            .into_bytes(),
        }
    }
}

/// Bind `127.0.0.1:0`, spawn the looping accept-and-respond task on `bridge_rt`,
/// and wrap it in a counted [`BridgeTestSse`] handle.
async fn spawn(response: Response) -> BridgeTestSse {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind local sse listener");
    let addr = listener.local_addr().expect("local addr");
    let payload = response.bytes();
    let task = bridge_rt().spawn(async move {
        loop {
            let Ok((mut stream, _)) = listener.accept().await else {
                return;
            };
            // Drain the request headers (until CRLFCRLF) — a GET/POST with no
            // body we care about.
            let mut buf = [0u8; 4096];
            let mut req = Vec::new();
            loop {
                match stream.read(&mut buf).await {
                    Ok(0) => break,
                    Ok(n) => {
                        req.extend_from_slice(&buf[..n]);
                        if req.windows(4).any(|w| w == b"\r\n\r\n") {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
            let _ = stream.write_all(&payload).await;
            let _ = stream.flush().await;
            // Small linger so the client reads the frames before EOF, then the
            // connection closes (drop) → clean EOF for the client.
            tokio::time::sleep(std::time::Duration::from_millis(30)).await;
        }
    });
    ACTIVE_SSE_SERVERS.fetch_add(1, Ordering::SeqCst);
    BridgeTestSse {
        base_url: format!("http://{addr}"),
        abort: task.abort_handle(),
        stopped: AtomicBool::new(false),
    }
}
