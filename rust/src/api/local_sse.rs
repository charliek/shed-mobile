//! A minimal in-process SSE server for the watcher/create slice proofs — the
//! same shape shed-core's own `rc_events`/`create_shed` tests use (a raw
//! socket writing a `200 text/event-stream` response + scripted frames), but
//! spawned on the bridge runtime so a bridged `Client` can hit it over real
//! reqwest/rustls-free plaintext HTTP. Binds `127.0.0.1:0`, serves each
//! accepted connection the given body then closes it (a clean EOF), looping so
//! a reconnecting watcher is served again.

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

use super::bridge_rt::bridge_rt;

/// Stand up a looping local SSE server that writes `body` (the SSE frames) on
/// every accepted connection, then closes it. Returns `http://127.0.0.1:<port>`
/// — the `base_url` a bridged `Client` is built against. The server task runs
/// on the bridge runtime until `body`'s owner (the caller) drops the returned
/// abort handle by tearing down the slice (the accept loop is aborted when the
/// watcher/create handle stops, via the same runtime shutdown path in tests).
pub(crate) async fn spawn_local_sse(body: &'static str) -> (String, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind local sse listener");
    let addr = listener.local_addr().expect("local addr");
    let handle = bridge_rt().spawn(async move {
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
            let _ = stream
                .write_all(
                    b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n",
                )
                .await;
            let _ = stream.write_all(body.as_bytes()).await;
            let _ = stream.flush().await;
            // Small linger so the client reads the frames before EOF, then the
            // connection closes (drop) → clean EOF for the client.
            tokio::time::sleep(std::time::Duration::from_millis(30)).await;
        }
    });
    (format!("http://{addr}"), handle)
}
