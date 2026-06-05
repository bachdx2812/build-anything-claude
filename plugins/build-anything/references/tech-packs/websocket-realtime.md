# Tech-pack — WebSocket / realtime (implementer reference)

> **When to consult:** `architecture.md#Stack` declares WebSocket / socket.io / SSE / WebRTC,
> OR `feature_surface[]`/`core_flows[]` include chat, messaging, presence, typing, live feed/notifications, collaborative editing.
> The multi-client proof (GATE-RT-PROPAGATE) WILL run — code so a message sent by client A reaches client B with no reload.
>
> This pack is principles + checklist, not a version-pinned API copy. It exists because realtime mechanics are the class of bug
> agents most often get wrong from memory (FB-clone field report: repeated WebSocket fixes). KISS — apply only what the feature needs.

## The one thing the gate checks
Two independent clients (separate browser contexts / tokens). A emits a unique marker → **B must observe it live, within budget, without reloading.** A single-client optimistic echo is NOT proof. Design for cross-client delivery from the start, not as an afterthought.

## Connection lifecycle (get this right first)
- **Auth on upgrade (SECURITY-CRITICAL).** Authenticate the handshake itself — validate the token in the `upgrade`/connection event and reject before joining any room. Never trust the first in-band message to carry identity. An unauthenticated socket that can subscribe = cross-tenant data leak. (Mirrors LAW-AUTH-RT for the socket layer.)
- **Reconnect with backoff + jitter.** Networks drop sockets constantly. Client auto-reconnects with exponential backoff + jitter (e.g. 0.5s → cap ~30s), and **re-subscribes to its rooms + re-syncs missed state** on reconnect (server replays since last-seen cursor, or client refetches). A socket that never reconnects = "chat randomly stops working."
- **Heartbeat / ping-pong.** Detect half-open connections: server pings on an interval, terminates sockets that miss N pongs; client treats missed pongs as a dropped link and reconnects. Without this, dead sockets linger and "online" lies.
- **Clean teardown.** On disconnect: leave rooms, clear presence, cancel timers. Leaks here cause ghost users + memory growth.

## Delivery semantics
- **Room / channel scoping.** Broadcast to the *room*, never globally. Authorize room membership on join (does this user belong to this conversation/tenant?). The gate's negative-isolation check fails a build where a client in another channel receives the marker — scope every emit.
- **Idempotent delivery + dedupe.** Assume at-least-once. Give each message a stable client-generated id; receivers dedupe by id. Reconnect-replay must not double-post.
- **Optimistic send + server reconcile.** Render the sender's message immediately with a `pending` state and the client id; when the server's authoritative echo returns (same id), reconcile (confirm / replace / mark failed). Never leave a message stuck `pending`.
- **Ordering.** Don't assume arrival order across reconnects. Order by a server timestamp / sequence, not receipt order.
- **Backpressure.** High-volume rooms: batch/coalesce emits, drop or sample presence/typing noise. Don't flush every keystroke to every client unthrottled.

## Persistence (the realtime-vs-stored split agents forget)
- Realtime transport delivers to *currently-connected* clients. **Also persist** messages/events so a client that was offline gets them on next load (history endpoint) — and so the 2nd client in the gate, if it connects after the emit, can still reconcile. Transport ≠ storage.

## Transport choice (from architecture, don't re-decide here)
- **WebSocket / socket.io** — bidirectional (chat, presence, collaborative editing).
- **SSE** — server→client only (live feeds, notifications); simpler, auto-reconnects, but no client→server channel.
- **WebRTC** — peer media (audio/video calls); has its own gate (GATE-CALL) — expose the `RTCPeerConnection` per `call.peer_accessor` under the E2E flag.

## E2E drivability (so the gate can prove it, not N/A)
Make the realtime surface drivable: stable selectors for the send input (`send_selector`) and the observed region (`observe_selector`); a deterministic login the probe can script (`realtime.login` + two `realtime.users`). Declare `realtime.{enabled,login,users,journeys}` in `.build-anything.json`. Undrivable surface ⇒ gate N/A ⇒ the build ships unproven.

## Anti-patterns (each = a real bug class)
- Optimistic echo only — sender sees the message, no one else does. **#1 false "it works".**
- No reconnect → first network blip kills realtime silently.
- Global broadcast → every user sees every room's traffic (leak + noise).
- Auth checked on REST but not on the socket upgrade → unauthenticated subscribe.
- Realtime-only, no persistence → refresh loses history; late joiner sees nothing.
- Flushing every keystroke unthrottled → fan-out storm at scale.

## Checklist before claiming done
- [ ] Handshake authenticated; unauthenticated upgrade rejected
- [ ] Client reconnects (backoff+jitter) and re-subscribes + re-syncs on reconnect
- [ ] Heartbeat/ping-pong drops dead sockets
- [ ] Emits scoped to authorized room; cross-room isolation holds
- [ ] Messages have stable ids; receivers dedupe; optimistic send reconciles
- [ ] Messages persisted; history endpoint serves offline/late clients
- [ ] `send_selector` + `observe_selector` stable; `realtime.*` declared for the probe
- [ ] Verified manually with TWO clients before handing to the gate
