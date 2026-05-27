# External system-design reference — `bachdx2812/system-design-advisor`

Repo: <https://github.com/bachdx2812/system-design-advisor>
References folder: <https://github.com/bachdx2812/system-design-advisor/tree/main/references>
Raw root: `https://raw.githubusercontent.com/bachdx2812/system-design-advisor/main/references/<FILE>`

**Usage contract:** the Stage 1.B Architect persona MUST consult this catalog, pick the topics that match the declared `product_type` + `scale_tier`, and fetch the relevant files (via WebFetch / `gh api` / shallow clone) before drafting `architecture.md` + `production-design.md`. Cite each consulted file by name in `production-design.md ## Boring-tech justification` or `architecture.md ## Trade-offs considered`.

The harness ships this static index so the agent never has to guess which file applies. Re-sync the index when the upstream repo adds new files (see §"How to refresh" below).

## Topic → file map

| Topic | File | When to consult |
|-------|------|------------------|
| Back-of-envelope sizing, latency budgets, capacity arithmetic | `fundamentals-and-estimation.md` | ALWAYS (every atom whose scale_tier ≥ growth). Drives `production-design.md ## Capacity model`. |
| Core architecture styles (monolith, modular monolith, microservices, hexagonal, event-driven) | `architecture-patterns.md` | When picking top-level shape in `architecture.md ## Stack`. |
| Distributed-systems primitives (consensus, replication, partition tolerance, sharding) | `distributed-patterns.md` | scale_tier ≥ scale OR product is multi-region OR realtime-collab. |
| Modern cloud-native patterns (CRDT, edge functions, serverless, streaming SSR) | `modern-patterns.md` | scale_tier ≥ growth AND product touches collab/realtime/edge. |
| Storage primitives, durability classes, object stores, block stores | `storage-and-infrastructure.md` | ALWAYS for media-heavy products (video / image / file-sharing). Drives stack.media_storage. |
| Database trade-offs (relational, document, wide-column, time-series, search) | `databases.md` | ALWAYS. Drives stack.database + `production-design.md ## Data lifecycle`. |
| Caching tiers, CDN topology, edge caches | `caching-and-cdn.md` | scale_tier ≥ growth OR product has hot read path (video catalog, search, feed). |
| DNS, load balancers (L4/L7), Anycast | `dns-and-load-balancing.md` | scale_tier ≥ scale OR multi-region. |
| Queues, brokers, protocols (Kafka, NATS, MQTT, AMQP, gRPC) | `queues-and-protocols.md` | Async pipelines (transcode, email, notification, ingestion). |
| Realtime, streaming protocols (WebSocket, SSE, WebRTC, HLS, DASH) | `real-time-and-streaming.md` | Video / chat / collab / live-stream products. |
| Search & indexing (inverted index, BM25, vector search) | `search-and-indexing.md` | Product has search UI (e-commerce, video catalog, knowledge base). |
| Data pipelines, ETL/ELT, OLAP, lakehouse | `data-processing-and-analytics.md` | Product has analytics dashboard, BI, recommendation training data. |
| Recommendation systems, candidate gen, ranking, ML serving | `recommendation-and-ml-systems.md` | Product has personalised feed, "for you", related-items. |
| Authentication, OAuth, OIDC, sessions, JWT pitfalls | `authentication-and-security-deep-dive.md` | ALWAYS for any product with login. |
| Multi-tenant patterns, collab data sync | `collaborative-and-multi-tenant.md` | Multi-tenant SaaS OR collab editing. |
| Anti-patterns + selection heuristics (when NOT to use X) | `anti-patterns-and-selection.md` | Reviewer cross-check — read before committing to non-boring tech. |
| End-to-end case studies (canonical YouTube / Twitter / Uber etc.) | `case-studies.md` | When product is a clone of canonical large system. |
| Low-level design patterns (OOP, GOF) | `low-level-design-patterns.md` | Atom touches API design / domain model. |
| Creational / Structural / Behavioral GOF patterns | `creational-patterns.md` / `structural-patterns.md` / `behavioral-patterns.md` | Same as above, deep dive per family. |
| Modern + interview deep-dives | `modern-and-interview.md` | Reviewer cross-check; useful when stack proposal needs defending. |
| Operational troubleshooting (debugging prod incidents) | `operational-troubleshooting.md` | `production-design.md ## Failure modes` + `## Observability story`. |
| Specialized systems (payments, geo, IoT, blockchain, time-series) | `specialized-systems.md` | Domain-specific products. |

## Worked example — `youtube-clone` at `growth` tier

Architect MUST read at minimum:
1. `fundamentals-and-estimation.md` — sizing DAU → RPS → storage → bandwidth
2. `storage-and-infrastructure.md` — object store (S3) + lifecycle for video segments
3. `caching-and-cdn.md` — CDN for HLS segments + thumbnail caching
4. `real-time-and-streaming.md` — HLS vs DASH, ABR ladder
5. `queues-and-protocols.md` — transcode worker queue (SQS / Kafka)
6. `databases.md` — Postgres for metadata + alternative for view counters
7. `search-and-indexing.md` — video catalog search
8. `case-studies.md` — YouTube case study section
9. `authentication-and-security-deep-dive.md` — uploader auth + signed URLs
10. `anti-patterns-and-selection.md` — sanity check against tier-disqualified packages

Then cite each consulted file in `production-design.md ## Boring-tech justification`.

## How to refresh this index

```bash
gh api repos/bachdx2812/system-design-advisor/contents/references \
  --jq '.[] | "\(.name)"'
```

If the upstream repo adds a new file, append a row to the topic→file map and update §"Worked example" if relevant.
