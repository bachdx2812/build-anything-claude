# Deploy runbook — youtube-clone

Atom: 260527-0141-youtube-like-share. Scale tier: **scale** (500K DAU). SLO: p95 watch-start < 2s, p95 API < 500ms, availability ≥ 99.5%.

## Pipeline order

1. `backend:lint` + `backend:test` + `frontend:lint` parallel
2. `db:invariants` against ephemeral postgres
3. `security:secrets` (no AKIA / sk-XXXX / hardcoded passwords)
4. `infra:plan` produces tfplan artifact
5. `infra:apply` — **manual approve** in GitLab UI

Skip nothing. A failed test must block merge — never `--no-verify`.

## Rollback

Two paths exist:

### Code rollback
```
git revert <merge-sha>
git push origin main
# CI re-runs full suite → deploys previous image
```

### Schema rollback
```
psql -h <aurora-host> -d ytclone -f .build-anything/atoms/260527-0141-youtube-like-share/schema/rollback.sql
```

⚠ `rollback.sql` drops every table FK-ordered. Use only during disaster recovery on a freshly restored snapshot. Production rollback path: `terraform apply -target=aws_rds_cluster.primary -var "aurora_engine_version=<prev>"` against a point-in-time-restore snapshot.

## RTO / RPO

| Metric | Target | Mechanism |
|--------|--------|-----------|
| RTO | < 30 min | Aurora multi-AZ failover (~ 60s), CloudFront DNS rotation (~ 5 min), ECS Fargate restart (~ 2 min) |
| RPO | < 5 min | Aurora continuous backup + S3 versioning + Kafka 7d retention |

## Disaster scenarios

| Scenario | Detect | Mitigate |
|----------|--------|----------|
| Aurora primary down | CloudWatch RDS DBLoad / Alarm `replica-lag > 10s` | Multi-AZ auto-failover; promote read replica |
| S3 raw bucket throttle | 503s in upload service logs | Increase prefix entropy; enable Transfer Acceleration |
| CloudFront 5xx surge | CloudWatch 5xxErrorRate > 1% | Pin to single edge POP; force cache invalidation |
| MSK broker loss | Lag alarm fires on `transcode.consumer` | Kafka rebalances; worker DLQ catches |
| Cognito outage | 5xx on /auth/* endpoints | Fall back to refresh-only mode; dev-mode tokens disabled |

## Pre-deploy checklist

- [ ] `go test ./...` green locally
- [ ] `staticcheck ./...` green
- [ ] migration applied + invariants ran against staging
- [ ] frontend `npm run typecheck` green
- [ ] secret scan empty
- [ ] terraform plan diff reviewed by 2nd engineer
- [ ] feature flag default = off
- [ ] alarms on new endpoints exist (or explicit skip with reason)

## Post-deploy verification

```
curl -sf https://api.prod/healthz | jq -e '.status == "ok"'
curl -sf https://api.prod/readyz  | jq -e '.ready == true'
# spot-check golden path
TOKEN=$(curl -sf https://api.prod/v1/auth/login -d '{"email":"smoke@x.com","password":"..."}' | jq -r .jwt)
curl -sf -H "Authorization: Bearer $TOKEN" https://api.prod/v1/feed/trending | jq '.videos | length'
```

If p95 watch-start regresses >10% within 30 min of cutover → automatic rollback via CloudWatch composite alarm + Lambda → ECS service revert to previous task-def.

## On-call

| Service | Primary | Secondary | Pager |
|---------|---------|-----------|-------|
| API | platform-oncall | infra-oncall | PagerDuty `api-prod` |
| Transcode | media-oncall | platform-oncall | PagerDuty `media-prod` |
| Aurora | dba-oncall | platform-oncall | PagerDuty `db-prod` |
| CloudFront/CDN | infra-oncall | platform-oncall | PagerDuty `edge-prod` |
