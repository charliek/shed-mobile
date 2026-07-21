# Servers & Sheds

## Servers

A **server** is one shed host (the on-device equivalent of a `~/.shed/config.yaml`
server entry). Each saved `ServerRecord` holds the host, SSH port, API URL, the
pinned TLS fingerprint, the pinned SSH host key, and the last minted control token.
Records are persisted in the platform `SecretStore`.

Add and remove servers from the server-list screen. Adding a server runs the
SSH-mint + fingerprint-confirm flow (see
[Transport & Security](../architecture/transport-security.md#trust-establishment-add-server)).

## Sheds

Opening a server lists its sheds (`GET /api/sheds`) over pinned TLS. Each shed
shows its name and status; actions:

| Action | Endpoint |
|---|---|
| Start | `POST /api/sheds/:name/start` |
| Stop | `POST /api/sheds/:name/stop` |
| Restart | client-side Stop then Start (shed-core has no atomic restart) |
| Delete | `DELETE /api/sheds/:name` (confirm dialog) |
| Open | Navigates to the shed's [RC sessions](rc-sessions.md). |

Both surfaces — the per-host list and the cross-host **Sheds** tab — render one
shared `ShedCard` widget, so they expose the same lifecycle actions (incl.
delete-with-confirm) at both widths. The shared `confirmShedDelete` dialog gates
every delete; a rapid second tap can't stack a second dialog. On mobile the
whole card also drills into the shed's sessions.

`ShedClient` (`lib/shed/shed_client.dart`) is a faithful port of the
orchestrator's `shedClient.ts`: a `401` invalidates the token and retries once
with a fresh, distinct token; upstream `{error:{code,message}}` bodies are
preserved.

## Creating a shed

The create screen streams live progress over Server-Sent Events
(`POST /api/sheds`, `postSse`). Enter a name and optionally a repo as
`owner/repo` text. Events arrive as:

| Event | Rendered as |
|---|---|
| `progress` | A `[phase] message` line. |
| `complete` | The finished shed. |
| `error` | `code: message` (the stream's own error, not an exception). |

A `401` on stream open re-mints once before any event is yielded.

!!! note "Repo entry"
    The MVP accepts a repo as typed `owner/repo` text. A GitHub repo picker
    (OAuth / public) is an architected-but-deferred seam.
