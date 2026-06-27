# In-App Terminal

The terminal attaches an [xterm.dart](https://pub.dev/packages/xterm) view to an
RC session's tmux pane (`tmux attach -t rc-<slug>`) over a host-key-pinned SSH
PTY. It is a port of the orchestrator's `rcAttach`.

Open it from the **terminal** button on any RC session tile.

## How it works

`PtySession` (`lib/ssh/pty_session.dart`) is a long-lived bidirectional PTY built
on the shared `withSshClient` primitive:

- `client.execute('tmux attach -t rc-<slug>', pty: SSHPtyConfig(width, height))`.
- Output (a broadcast `Stream<Uint8List>`) → terminal, via a chunked UTF-8
  decoder that buffers multibyte sequences split across SSH packets.
- Keystrokes (xterm `onOutput`) → remote stdin; viewport changes (`onResize`) →
  `resizeTerminal`. Dimensions are clamped to `[1, 1000]`.

The widget owns the session (built via `buildPtySession`) and tears it down in
`dispose`. `_pty` is assigned before `start()` so disposing mid-connect closes the
session deterministically. `write`/`resize` tolerate the channel-teardown race.

## Detach vs. kill

Leaving the screen (the back button is labeled **Detach**) closes the SSH
connection, which **detaches** tmux — the RC session keeps running. Reopen the
terminal to reattach. To actually end the session, use **kill** on the RC tile.

## State

The screen shows a connecting spinner, the live terminal, or a connect error with
a **Reconnect** action. When the remote process exits, a "Session ended" banner
appears with reconnect.

## Platform notes

- **Android:** the soft keyboard is handled by `windowSoftInputMode=adjustResize`
  plus the Scaffold; attaching also starts a
  [foreground service](../platforms/android.md#foreground-service) so the session
  survives backgrounding.
- **Rekey:** dartssh2 is pinned to 2.18.0 for its AES-GCM rekey fix; multi-minute
  sessions across a rekey are part of the manual acceptance.
