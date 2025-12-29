# High Level Design: Remote OpenCode on a VPS (Tailscale) + iOS Client

## Overview

We run a single headless OpenCode server on a VPS and access it privately from an iOS app over Tailscale. The server can operate on multiple repositories on disk by scoping each API request to a project directory via `x-opencode-directory` (or `?directory=`). This yields:

- A **single** long-running OpenCode API service on the VPS
- **Multiple projects** (repos) served by the same process
- A dedicated **control workspace** for VPS-wide / cross-project orchestration
- A private, TLS-terminated endpoint via **`tailscale serve`** that is reachable only inside the tailnet

## Goals

- **Private remote access** from iOS without exposing OpenCode to the public internet.
- **One-server, many-projects**: create sessions in any repo directory on the VPS.
- **Streaming UX** on iOS (tool execution + assistant output + status) via SSE.
- **Safe remote execution**: permission prompts surfaced to iOS, with explicit approve/deny flows.
- **Reproducible ops**: service management, upgrades, backups, and recovery documented.

## Non-goals

- Multi-tenant untrusted user hosting (this is a personal / small-team setup).
- Public internet access (we rely on Tailscale rather than public reverse proxies).
- Full device-to-device “drive TUI remotely” parity (the iOS app is an API client).

## System Architecture

### Network / Trust Boundary

- The VPS runs `opencode serve` bound to `127.0.0.1:4096` (not directly reachable on the public network).
- Tailscale provides:
  - Node identity
  - Private routing
  - Optional policy enforcement via ACLs
- `tailscale serve` exposes a **tailnet-only HTTPS URL** that reverse-proxies to `http://127.0.0.1:4096`.

**Primary trust boundary**: tailnet membership + ACLs. (Optional: add application-level auth later if desired.)

### Logical Data Flow

1. iOS app connects to the OpenCode API at `https://<vps>.<tailnet>.ts.net/`.
2. For each request, the app supplies the target workspace with:
   - `x-opencode-directory: /home/opencode/projects/<repo>` (project mode), or
   - `x-opencode-directory: /home/opencode/control` (control mode)
3. The OpenCode server routes the request into an internal per-directory `Instance`.
4. The iOS app:
   - Starts prompts via `POST /session/:sessionID/message` (streaming response) or `POST /session/:sessionID/prompt_async` (fire-and-forget).
   - Subscribes to events via SSE (`GET /event?directory=...` or `GET /global/event`) to render streaming output and tool progress.
   - Responds to permission requests via `POST /session/:sessionID/permissions/:permissionID`.

## VPS Design

### Processes

- **`tailscaled`**: Tailscale daemon
- **`opencode serve`**: OpenCode API server (headless)
- **`tailscale serve`**: tailnet-only HTTPS reverse proxy to OpenCode

### Directory Layout

Recommended:

- **`/home/opencode/control`**
  - “Meta” workspace: runbooks, scripts, repo inventory, shared notes
  - Optional: a small git repo to version operational scripts/config
- **`/home/opencode/projects/<repo>`**
  - One folder per cloned repository

Rationale:

- Keeps cross-project automation and notes separated from application repos.
- Makes it explicit which directory the iOS client should use for “control” vs “project” sessions.

### GitHub Access

- The VPS user (`opencode`) holds an SSH key with access to GitHub (deploy keys or a dedicated machine user).
- Repositories are cloned into `/home/opencode/projects/…`.

Operational note:

- Prefer **deploy keys** per repo for least privilege, unless you explicitly need broad repo access.

### Service Management

Run OpenCode as a `systemd` service bound to loopback:

- `ExecStart: opencode serve --hostname 127.0.0.1 --port 4096`
- `WorkingDirectory: /home/opencode/control`
- Environment variables (provider keys, config) are stored in `systemd` environment / env files, not checked into git.

`tailscale serve` should be configured once and verified with:

- `tailscale serve status`

### Scaling Model

This design is a **single host** with:

- One OpenCode server process
- Many concurrent sessions across many directories

If resource contention grows (CPU/RAM), scale by:

- Increasing droplet size first
- Adding per-project limits in the iOS app (concurrency)
- Potentially running multiple OpenCode server processes only if isolation becomes necessary

## OpenCode Server Capabilities Used

### Session management

- Create sessions: `POST /session`
- List sessions: `GET /session`
- Send prompts: `POST /session/:sessionID/message` (streaming) or `POST /session/:sessionID/prompt_async`
- Abort: `POST /session/:sessionID/abort`

### Event streaming

- Project-scoped SSE: `GET /event?directory=...` (recommended for iOS UI per-project views)
- Global SSE: `GET /global/event` (useful for a global activity feed)

### Permissions

- List pending permissions: `GET /permission`
- Respond: `POST /session/:sessionID/permissions/:permissionID` with `{ response: "once" | "always" | "reject" }`

## iOS Client Design

### Core responsibilities

- **Session lifecycle**:
  - create, resume, list, delete (optional)
- **Prompting**:
  - send user text + file attachments (optional)
  - support both streaming and async flows
- **Streaming UI**:
  - consume SSE events
  - render assistant text, tool calls, step boundaries, and session status
- **Permissions UI**:
  - show “approve / deny” prompts for actions requiring confirmation
  - allow “Allow once” vs “Always allow” (with clear UX implications)

### Workspace selection (project vs control)

All requests set **one** of the following:

- `x-opencode-directory: /home/opencode/control`
- `x-opencode-directory: /home/opencode/projects/<repo>`

Important:

- A session is effectively **scoped** to the directory/instance it was created under.
- The iOS app should store `(sessionID, directory)` together and always send them together.

### SSE handling

Recommended approach:

- Use `GET /event?directory=...` for the currently selected project.
- Optionally also open `GET /global/event` for a “background activity” badge or global timeline.

### UX modes

- **Project mode**: default chat experience for a selected repo.
- **Control mode**: “VPS / Ops” chat for cross-project tasks (sync repos, run scripts, apply global config).

## Security & Safety

### Tailscale ACLs

Use Tailscale ACLs to restrict which devices/users can access the VPS and/or the `tailscale serve` HTTPS endpoint.

### Least privilege on the VPS

- Run as a non-root user (`opencode`).
- Avoid blanket passwordless `sudo`. If elevated actions are needed, allowlist specific commands.

### Permissions as the safety valve

The iOS app is the human-in-the-loop surface:

- Treat permission prompts as mandatory for risky tools (shell, edits outside repo boundaries, etc.).
- Provide clear display of the command/file targets before approval.

### Secrets handling

- Keep provider API keys and credentials out of repositories and logs.
- Prefer `systemd` environment files or secret stores over plaintext files in repo.

## Operations

### Upgrades

- Update OpenCode binary periodically (pin versions if needed for stability).
- Restart `opencode` via `systemctl restart opencode`.
- Verify health with `GET /global/health` and a quick prompt smoke test.

### Backups

Back up at least:

- `/home/opencode/projects` (repos can be re-cloned, but local changes matter)
- `/home/opencode/control`
- OpenCode state/config directories (if stored outside those trees)

### Observability

Minimum:

- `journalctl -u opencode` for server logs
- iOS app shows last error event for the session

Optional:

- Lightweight monitoring to alert if the `opencode` service is down

## Failure Modes & Recovery

- **Tailscale down**: iOS can’t connect; restart `tailscaled`, verify tailnet status.
- **OpenCode down**: restart `opencode` service; check logs; verify provider credentials.
- **Repo permission issues**: ensure correct ownership for `/home/opencode/projects/*` and valid GitHub SSH key.
- **Runaway tool usage**: use session abort endpoint; consider tighter permissions policies.

## Future Enhancements

- **Application-layer auth** (in addition to Tailscale) with per-device tokens.
- **Repo registry API** (a small service or scripts) for listing/creating repos and mapping friendly names → directories.
- **Per-project quotas** (concurrency limits, maximum running sessions).
- **Audit trail**: persist permission approvals and high-level actions to the control workspace.


