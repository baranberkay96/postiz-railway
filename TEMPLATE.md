# Postiz v2 AI Social Media Scheduler — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | Postiz v2 AI Social Media Scheduler |
| Description | Schedule posts to X, LinkedIn, Instagram and more. Full Temporal stack. (76 characters) |
| Category | Automation |
| Tags | postiz, social-media, scheduler, marketing, temporal, ai |

Name = LISTINGS.md name with the version label `v2` (Postiz tags releases as `vX.Y.Z`; pinned tag `v2.25.0`). The description is unchanged: Postiz has required a Temporal stack since v2.12.0 (docs.postiz.com configuration reference), and this template ships it.

## Base market template

**Base: `postiz`** ("Postiz [Updated Oct '26] …", 516 projects / 201 active, category CMS). It is the only market template that runs Temporal, which current Postiz requires. Kept: the overall service set (Postiz, Postgres, Redis, Temporal server, Elasticsearch visibility, Temporal UI), the `/uploads` volume, `STORAGE_PROVIDER=local`, the URL variables and `PORT=3000` with the public domain on port 5000. Fixed or replaced: everything listed under "Improvements over market templates".

Other market templates reviewed:
- `deploy-postiz` (239 projects): deliberately frozen at Postiz v2.11.3, "the last version before Temporal became a required dependency". Rejected as a base (outdated app, `NOT_SECURED=true`). Taken: private-network `REDIS_URL` wiring and explicit restart policies.
- `Rd76MM` (733 projects): Postiz v2.11.3 without Temporal; connects to Postgres and Redis through their **public** TCP proxy URLs (egress cost, public exposure); Redis volume mounted at `/bitnami` on the official `redis:7` image, which stores data in `/data`, so Redis data is not persisted; `NOT_SECURED='false'` (Postiz treats any non-empty value as "not secured"). Nothing taken.

`_upstream` license status:
- `Shinyduo/elasticsearch-railway` (used by the `postiz` market template for Elasticsearch): **no license** (GitHub API returns no license; no LICENSE file). Read for ideas only; no files or text copied. This template uses the official Elastic image with its own configuration instead.

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| Postiz | `ghcr.io/gitroomhq/postiz-app` | `v2.25.0` | 2026-10-02 (GitHub release) | 2026-10-10 |
| Temporal | `temporalio/server` + tools from `temporalio/admin-tools` (built from `services/temporal`) | `1.32.1` | 2026-10-08 | 2026-10-10 |
| Elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch` (built from `services/elasticsearch`) | `8.19.23` | 2026-10-06 | 2026-10-10 |
| Temporal UI | `temporalio/ui` (built from `services/temporal-ui`) | `2.55.0` | 2026-10-01 | 2026-10-10 |
| Temporal UI (auth proxy) | `caddy` binary copied into the Temporal UI image | `2.11.7-alpine` | 2026-10-06 (image published) | 2026-10-10 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base definition | 2026-10-10 |
| Redis | `redis` | `8.2` | Railway base definition | 2026-10-10 |

All tags were confirmed to exist in their registries (GHCR manifest, Docker Hub tag API, docker.elastic.co manifest) on 2026-10-10.

## Architecture

Six services. Two have public domains (Postiz, Temporal UI behind basic auth). Everything else is private-network only.

```
                     Internet (HTTPS terminated at the Railway edge)
                       |                                   |
            Postiz domain -> :5000              Temporal UI domain -> :8080
                       |                                   |
 +---------------------v---------------------+   +---------v-----------------+
 | Postiz (one container, pm2 + nginx)       |   | Temporal UI               |
 |  nginx :5000  /        -> frontend :4200  |   |  Caddy :8080 (basic auth) |
 |               /api/*   -> backend  :3000  |   |   -> ui-server :8081      |
 |               /uploads -> volume /uploads |   +---------+-----------------+
 |  orchestrator: Temporal workers           |             | gRPC 7233
 +-----+-------------+-------------+---------+             |
       | 5432        | 6379        | gRPC 7233             |
       |             |             v                       v
       |             |     +-------+-----------------------+---+
       |             |     | Temporal (single-node server)     |
       |             |     +-------+--------------------+------+
       |             |             | 5432 (db temporal) | 9200 (basic auth)
 +-----v-------------+--+          |           +--------v--------------+
 | Postgres             |<---------+           | Elasticsearch         |
 |  db railway (Postiz) |                      |  Temporal visibility  |
 |  db temporal         |   +-------+          |  index                |
 +----------------------+   | Redis |          +-----------------------+
                            +-------+
```

Design decisions:

1. **Temporal is required.** Postiz v2.25.0 starts Temporal workers in its `orchestrator` app and schedules every post as a Temporal workflow. Without Temporal the backend fails at boot (it registers search attributes on startup).
2. **Temporal shares the `Postgres` service, in its own database `temporal`.** Temporal supports any PostgreSQL 12+ database; the upstream compose file uses a second Postgres container only for isolation. Sharing saves a service and a volume. Postiz uses database `railway`, Temporal uses `temporal` (created by the Temporal entrypoint). Isolation trade-off and how to split it out are in "Open questions".
3. **Elasticsearch is kept as the visibility store.** It has a functional role, not only a UI one: when a post is edited or deleted, Postiz lists running workflows with the visibility query `postId="…" AND ExecutionStatus="Running"` on its custom `Text` search attributes `organizationId` and `postId`. Both the upstream Postiz compose file and Temporal's own reference compose (`temporalio/samples-server`) use Elasticsearch for this. Temporal could use Postgres advanced visibility instead (saves about 1 GB RAM), but that is not the configuration upstream runs. Version: 8.19.x, because 7.17 (upstream's pin) reached end of life on 2026-01-15 and Temporal supports Elasticsearch v8 (tested in Temporal's CI).
4. **No `temporalio/auto-setup`.** That image was last published at 1.29.7. The template uses `temporalio/server:1.32.1` with the admin-tools binaries copied in and a bootstrap entrypoint that, on every boot, runs `temporal-sql-tool create / setup-schema -v 0.0 / update-schema`, `temporal-elasticsearch-tool setup-schema / create-index / update-schema`, starts the server, then creates the namespace and the `organizationId`/`postId` search attributes if missing. Every step is idempotent (checked in the tool sources: duplicate database is ignored, setup-schema skips when the version is above 0.0, update-schema applies only newer versions, create-index skips an existing index). The plain server image also has no dynamic config file and refuses to start without one; the image adds `dynamicconfig/railway.yaml`.
5. **Temporal UI has a public domain behind HTTP basic auth.** Temporal UI has no built-in password login, so Caddy runs in the same container in front of it with a generated password. It is useful for diagnosing stuck or failed posts (workflow history, retries, cancel or terminate). Set `TEMPORAL_DISABLE_WRITE_ACTIONS=true` for a read-only UI, or delete the service; Postiz does not depend on it.
6. **Uploads use a local volume, not a Railway Bucket.** Postiz v2.25.0 supports only `local` and `cloudflare` storage, and the Cloudflare provider hard-codes the endpoint `https://<account>.r2.cloudflarestorage.com`, so it cannot point at a Railway Bucket. Railway Buckets are also private, while social networks fetch media by public URL. The image's nginx serves `/uploads/` from the volume at `https://<domain>/uploads/…`, which is what the networks need.
7. **Registration closed by default and first sign-up still works.** In the Postiz source, `DISABLE_REGISTRATION=true` still allows sign-up while no organization exists. The first visitor creates the owner account, then sign-up closes. Set it to `false` temporarily to let invited teammates create accounts.
8. **`NOT_SECURED` is not set at all.** Postiz checks it for truthiness, so both `"true"` and `"false"` disable `secure`/`httpOnly` auth cookies. Railway serves HTTPS, so the secure default is correct.
9. **Networking.** Temporal binds `::` (dual stack). Elasticsearch binds the HTTP wildcard (`0.0.0.0`, which the JVM opens as a dual-stack socket). Redis is reached by ioredis with `?family=0` (Railway's documented setting for IPv6 private networking). The Postiz image's nginx listens on 5000 for the public domain only.

## Services

### Postiz
- Source: image `ghcr.io/gitroomhq/postiz-app:v2.25.0`. One container runs nginx (:5000), frontend (Next.js :4200), backend (NestJS :3000) and orchestrator (Temporal workers, health :3002) under pm2. On every start, the image runs `prisma db push` (upstream behaviour).
- Start command: image default. Pre-deploy: none.
- Healthcheck: `/auth/can-register` on `PORT=3000` (backend), timeout 600 s. With `DISABLE_REGISTRATION=true` this route runs a database query. The backend also only comes up once Temporal is reachable, so the check covers DB and Temporal readiness. The long timeout covers the first deploy, when Temporal waits for Elasticsearch.
- Public domain: yes, target port 5000 (nginx). TCP proxy: none.
- Volume: `/uploads`.
- Restart: ON_FAILURE, 10 retries. Replicas: 1 (has a volume). Cron: none.

| Variable | Value | Description |
|---|---|---|
| PORT | `3000` | Backend port inside the container; Railway healthcheck port |
| MAIN_URL | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Primary public URL |
| FRONTEND_URL | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Browser URL; OAuth redirects, cookies, upload links |
| NEXT_PUBLIC_BACKEND_URL | `https://${{RAILWAY_PUBLIC_DOMAIN}}/api` | Browser-facing backend URL |
| BACKEND_INTERNAL_URL | `http://localhost:3000` | Frontend server to backend, same container |
| JWT_SECRET | `${{secret(64)}}` | Session token signing |
| DATABASE_URL | `${{Postgres.DATABASE_URL}}` | Postiz database (private network) |
| REDIS_URL | `${{Redis.REDIS_URL}}?family=0` | Redis (private network, IPv4+IPv6) |
| TEMPORAL_ADDRESS | `${{Temporal.RAILWAY_PRIVATE_DOMAIN}}:7233` | Temporal gRPC |
| TEMPORAL_NAMESPACE | `${{Temporal.DEFAULT_NAMESPACE}}` | Namespace (`default`) |
| IS_GENERAL | `true` | Self-hosted product mode (upstream value) |
| RUN_CRON | `true` | Starts the missed-post recovery workflow |
| DISABLE_REGISTRATION | `true` | Only the first account can sign up |
| STORAGE_PROVIDER | `local` | Media on the volume |
| UPLOAD_DIRECTORY | `/uploads` | Must match the volume and nginx alias |
| NEXT_PUBLIC_UPLOAD_STATIC_DIRECTORY | `/uploads` | Public prefix for uploads (the name the v2.25.0 source reads) |
| API_LIMIT | `30` | Public API hourly post limit (upstream value) |
| EMAIL_PROVIDER, RESEND_API_KEY, EMAIL_FROM_ADDRESS, EMAIL_FROM_NAME | empty | Optional email; empty provider = accounts auto-activated |
| OPENAI_API_KEY | empty | Optional AI features |
| X_API_KEY / X_API_SECRET, LINKEDIN_CLIENT_ID / _SECRET, FACEBOOK_APP_ID / _SECRET, INSTAGRAM_APP_ID / _SECRET, THREADS_APP_ID / _SECRET, YOUTUBE_CLIENT_ID / _SECRET, TIKTOK_CLIENT_ID / _SECRET, REDDIT_CLIENT_ID / _SECRET, PINTEREST_CLIENT_ID / _SECRET, MASTODON_URL / _CLIENT_ID / _CLIENT_SECRET | empty (`MASTODON_URL=https://mastodon.social`) | Optional provider app credentials; each network needs its own developer app with redirect URI `https://<postiz-domain>/integrations/social/<provider>` (see Postiz provider docs) |

Further providers (Discord, Slack, Dribbble, Tumblr, LinkedIn pages, etc.) use the variables documented in Postiz's `.env.example`; add them on the service when needed.

### Temporal
- Source: repo `baranberkay96/postiz-railway`, root `/services/temporal` (Dockerfile: `temporalio/server:1.32.1` + `temporal`, `temporal-sql-tool`, `temporal-elasticsearch-tool` and `/etc/temporal/schema` from `temporalio/admin-tools:1.32.1`, dynamic config, bootstrap entrypoint).
- Start command: image CMD `/etc/temporal/railway-entrypoint.sh`. Pre-deploy: none (bootstrap waits for Postgres/Elasticsearch at runtime because Railway starts services in parallel).
- Healthcheck: `/api/v1/system-info` (frontend HTTP API) on `PORT=7243`, timeout 600 s.
- Public domain: none. TCP proxy: none. Volume: none (state lives in Postgres and Elasticsearch).
- Restart: ON_FAILURE, 10 retries. Replicas: 1 (single-node cluster config). Cron: none.

| Variable | Value | Description |
|---|---|---|
| PORT | `7243` | Healthcheck port (HTTP API) |
| DB | `postgres12` | SQL plugin |
| POSTGRES_SEEDS | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` | Postgres host |
| DB_PORT | `${{Postgres.PGPORT}}` | Postgres port |
| POSTGRES_USER | `${{Postgres.PGUSER}}` | Postgres user |
| POSTGRES_PWD | `${{Postgres.PGPASSWORD}}` | Postgres password |
| DBNAME | `temporal` | Temporal database (auto-created and migrated) |
| SQL_MAX_CONNS | `20` | Connection cap toward the shared Postgres |
| ENABLE_ES | `true` | Elasticsearch visibility |
| ES_SEEDS | `${{Elasticsearch.RAILWAY_PRIVATE_DOMAIN}}` | Elasticsearch host |
| ES_PORT / ES_SCHEME / ES_VERSION | `9200` / `http` / `v8` | Elasticsearch connection |
| ES_USER / ES_PWD | `elastic` / `${{Elasticsearch.ELASTIC_PASSWORD}}` | Elasticsearch credentials |
| ES_VIS_INDEX | `temporal_visibility_v1` | Visibility index (auto-created and upgraded) |
| NUM_HISTORY_SHARDS | `4` | Fixed at first boot |
| BIND_ON_IP | `::` | Dual-stack listen |
| TEMPORAL_BROADCAST_ADDRESS | `127.0.0.1` | Single-node self address |
| TEMPORAL_ALLOW_NO_AUTH | `true` | No authorizer (private network only) |
| DEFAULT_NAMESPACE | `default` | Namespace created on boot |
| DEFAULT_NAMESPACE_RETENTION | `72h` | Closed-workflow retention at creation |
| LOG_LEVEL | `info` | Server log level |
| RAILWAY_DEPLOYMENT_DRAINING_SECONDS | `20` | Clean shutdown window |

### Elasticsearch
- Source: repo `baranberkay96/postiz-railway`, root `/services/elasticsearch` (official 8.19.23 image + `elasticsearch.yml`, `roles.yml`, ownership/privilege-drop entrypoint).
- Start command: image ENTRYPOINT (tini → `railway-entrypoint.sh` → official `docker-entrypoint.sh` as uid 1000). Pre-deploy: none.
- Healthcheck: `/_cluster/health?wait_for_status=yellow&timeout=5s` on `PORT=9200`, timeout 300 s. Anonymous requests have only the `monitor` cluster privilege, so this works without exposing documents.
- Public domain: none. TCP proxy: none.
- Volume: `/usr/share/elasticsearch/data`.
- Restart: ON_FAILURE, 10 retries. Replicas: 1. Cron: none.
- Config highlights: single-node, `node.store.allow_mmap: false` (no `vm.max_map_count` on Railway), security on (basic auth, no TLS on the private network), ML/Watcher/GeoIP downloader off, absolute disk watermarks (1gb/512mb/256mb free).

| Variable | Value | Description |
|---|---|---|
| PORT | `9200` | Healthcheck port |
| ELASTIC_PASSWORD | `${{secret(32, "a-zA-Z0-9")}}` (alphanumeric alphabet) | `elastic` user password; set once before first deploy |
| ES_JAVA_OPTS | `-Xms512m -Xmx512m` | Explicit heap (otherwise sized from the container limit) |
| RAILWAY_DEPLOYMENT_DRAINING_SECONDS | `30` | Clean shutdown window |

### Temporal UI
- Source: repo `baranberkay96/postiz-railway`, root `/services/temporal-ui` (`temporalio/ui:2.55.0` + Caddy 2.11.7 binary, `Caddyfile`, `start.sh`).
- Start command: image ENTRYPOINT `/etc/railway/start.sh` (bcrypt-hashes the password, starts ui-server on 8081 and Caddy on `$PORT`, exits if either stops). Pre-deploy: none.
- Healthcheck: `/healthz` (unauthenticated, proxied to the UI server), timeout 300 s.
- Public domain: yes, target port 8080 (basic auth). TCP proxy: none. Volume: none.
- Restart: ON_FAILURE, 10 retries. Replicas: 1. Cron: none.

| Variable | Value | Description |
|---|---|---|
| PORT | `8080` | Caddy listen port |
| TEMPORAL_UI_USERNAME | `admin` | Basic-auth user |
| TEMPORAL_UI_PASSWORD | `${{secret(24, "a-zA-Z0-9")}}` (alphanumeric alphabet) | Basic-auth password |
| TEMPORAL_ADDRESS | `${{Temporal.RAILWAY_PRIVATE_DOMAIN}}:7233` | Temporal gRPC |
| TEMPORAL_DEFAULT_NAMESPACE | `${{Temporal.DEFAULT_NAMESPACE}}` | Default namespace shown |
| TEMPORAL_CORS_ORIGINS | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Allowed origin |
| TEMPORAL_DISABLE_WRITE_ACTIONS | `false` | `true` = read-only UI |

### Postgres
- Source: image `ghcr.io/railwayapp-templates/postgres-ssl:18`, copied verbatim from `_railway-base/postgres.json` (service name `Postgres`).
- Healthcheck: none (Railway base). Public domain/TCP proxy: none. Volume: `/var/lib/postgresql/data`. Restart: platform default. Replicas: 1.
- Databases: `railway` (Postiz, created by the image) and `temporal` (created by the Temporal entrypoint).

| Variable | Value | Description |
|---|---|---|
| PGDATA | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized |
| PGHOST | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| PGPORT | `5432` | Port to connect to Postgres. |
| PGUSER | `${{ POSTGRES_USER }}` | Required variable for Data panel |
| PGDATABASE | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| PGPASSWORD | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel |
| POSTGRES_DB | `railway` | Default database created when image is started. |
| DATABASE_URL | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| POSTGRES_USER | `postgres` | User to connect to Postgres DB |
| SSL_CERT_DAYS | `820` | SSL certificate expiry in days. |
| POSTGRES_PASSWORD | `${{ secret(32, "a-zA-Z") }}` (letters alphabet, as in base) | Password to connect to DB |
| RAILWAY_DEPLOYMENT_DRAINING_SECONDS | `60` | Allow Postgres to cleanly shut down |

### Redis
- Source: image `redis:8.2`, copied verbatim from `_railway-base/redis.json` (service name `Redis`), including its start command (`--requirepass`, RDB save every 60 s, data in the volume).
- Healthcheck: none (Railway base). Public domain/TCP proxy: none. Volume: `/data`. Restart: platform default. Replicas: 1.

| Variable | Value | Description |
|---|---|---|
| REDISHOST | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname |
| REDISPORT | `6379` | Port that Redis listens on |
| REDISUSER | `default` | Username for authenticating with Redis |
| REDIS_URL | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Private network connection string |
| REDISPASSWORD | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD |
| REDIS_PASSWORD | `${{ secret(32, "a-zA-Z") }}` (letters alphabet, as in base) | Randomly generated password |

No Bucket (see design decision 6).

## Improvements over market templates

1. **Current Postiz**: `v2.25.0` instead of `v2.11.3` (all three market templates).
2. **Supported Temporal without auto-setup**: pinned `temporalio/server:1.32.1` with an idempotent bootstrap, instead of untagged `temporalio/auto-setup` (no longer published after 1.29.7, so "latest" is stale). SQL and Elasticsearch schema upgrades run automatically on every boot.
3. **Namespace and Postiz search attributes are pre-created**, so first-boot ordering between Postiz and Temporal is not left to chance.
4. **Idle `temporal-admin-tools` container removed** (it only ran `sleep infinity`). The tools are baked into the Temporal image.
5. **One Postgres instead of two**: Temporal uses its own `temporal` database in the shared `Postgres` service (one service and one volume fewer).
6. **Elasticsearch from the official image, supported version, generated password**: `8.19.23` with this template's own configuration, instead of an unlicensed third-party repo with the password `1234`. Heap is explicit, mmap is disabled for Railway, unused features are off, and there is a healthcheck.
7. **Temporal UI protected**: basic auth with a generated password, CORS limited to its own domain. In the market template the UI is public, unauthenticated, and has full write actions.
8. **`NOT_SECURED` removed**: the market templates set it to `"true"` or `"false"`, and either value disables secure/httpOnly auth cookies in Postiz.
9. **Registration closed by default** (`DISABLE_REGISTRATION=true`) while the first owner sign-up still works (verified in source).
10. **Healthchecks on every HTTP service**: Postiz backend readiness (DB + Temporal), Temporal HTTP API, Elasticsearch cluster health, Temporal UI.
11. **No public database endpoints**: no TCP proxies on Postgres or Redis (the `postiz` and `Rd76MM` market templates expose them), and no public URLs between services.
12. **IPv6-ready private networking**: Temporal binds `::`, Elasticsearch binds a dual-stack wildcard, Redis URL carries `family=0` for ioredis.
13. **All images pinned** (the market template uses untagged `temporalio/*` images).
14. **Correct upload variable**: `NEXT_PUBLIC_UPLOAD_STATIC_DIRECTORY` (read by the v2.25.0 source) instead of `NEXT_PUBLIC_UPLOAD_DIRECTORY` (not read). The unused `BACKEND_URL` and `BACK_END_PORT` are dropped.
15. **Every variable described**; social-network and AI keys listed as optional with empty defaults; email activation behaviour documented.

## Resource estimate

Estimates for a single team with a few connected channels. Not measured on Railway.

| Service | Idle RAM | Typical RAM | Typical vCPU | Volume |
|---|---|---|---|---|
| Postiz (nginx + 3 Node apps) | 0.80 GB | 1.20 GB | 0.30 (idle 0.05) | ~2 GB uploads |
| Postgres | 0.10 GB | 0.25 GB | 0.10 (idle 0.02) | ~1 GB |
| Redis | 0.02 GB | 0.05 GB | 0.02 (idle 0.01) | <0.1 GB |
| Temporal | 0.20 GB | 0.35 GB | 0.15 (idle 0.05) | — |
| Elasticsearch (512 MB heap) | 0.90 GB | 1.10 GB | 0.10 (idle 0.03) | ~1 GB |
| Temporal UI + Caddy | 0.05 GB | 0.08 GB | 0.01 (idle 0.005) | — |
| **Total** | **2.07 GB** | **3.03 GB** | **0.68 (idle 0.17)** | **~4.1 GB** |

Monthly cost at Railway prices (RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month), before any plan usage credit:
- **Idle**: 2.07 GB × $10 = $20.70 + 0.17 vCPU × $20 = $3.40 + 4.1 GB × $0.15 = $0.62 → **about $25/month**.
- **Typical**: 3.03 GB × $10 = $30.30 + 0.68 vCPU × $20 = $13.60 + $0.62 → **about $45/month**.
- Lowering `ES_JAVA_OPTS` to `-Xms256m -Xmx256m` (upstream's value) saves about 0.25 GB (~$2.50/month) at the cost of headroom.

Minimum plan: **Hobby**. Postiz and Elasticsearch each need about 1 GB, which is at or above the Trial plan's 1 GB per-service limit. Hobby (up to 48 GB RAM and 5 GB volume per service) is enough. Use Pro if uploads will exceed 5 GB on the Postiz volume.

## Verification checklist

1. **Builds**: the three repo services (Temporal, Elasticsearch, Temporal UI) build. Image services pull `postiz-app:v2.25.0`, `postgres-ssl:18`, `redis:8.2`.
2. **Elasticsearch**: the deployment turns healthy. Logs show the ownership step (first boot only), "started", and no bootstrap-check or mmap errors.
3. **Temporal**: logs show the SQL schema steps, the Elasticsearch index steps and `[railway-entrypoint] Bootstrap complete: namespace 'default' is ready`. The `/api/v1/system-info` healthcheck passes. The Postgres Data panel shows a `temporal` database next to `railway`.
4. **Postiz health**: the `/auth/can-register` healthcheck passes. `https://<postiz-domain>/` loads the login page.
5. **First login**: register the owner account (no email needed while `EMAIL_PROVIDER` is empty). In a private window, the sign-up page then shows "Registration is disabled".
6. **Uploads**: upload an image in the media library. Its `https://<postiz-domain>/uploads/...` URL opens without login.
7. **Worker job**: connect a Bluesky account (handle + app password, no app keys needed) and schedule a post 2–3 minutes ahead. It publishes. In Temporal UI the post's workflow completes and shows the `postId` search attribute.
8. **Visibility query**: schedule another post, then edit its time or delete it. The old workflow is cancelled or terminated in Temporal UI. This exercises the Elasticsearch-backed `postId` query.
9. **Temporal UI auth**: the domain prompts for basic auth; a wrong password gets 401, the generated password works; the `default` namespace shows `missing-post-workflow` running.
10. **Persistence**: redeploy all services. The account, connected channel, uploaded media and scheduled posts survive. Temporal logs show the schema steps as no-ops; the Elasticsearch index still exists.
11. **Recovery**: restart Elasticsearch alone, then Postgres alone. Temporal and Postiz reconnect without manual steps (watch for crash loops).
12. **Scaling**: confirm vertical limits are sufficient (Postiz has a volume and cannot use replicas; Temporal is single-node by design).

## Open questions

- **Not deployed**: this package was prepared as local files only. All runtime behaviour above was derived from upstream sources and docs and needs the verification checklist on a real Railway project.
- **Elasticsearch privilege drop** uses coreutils `chroot --userspec=1000:0 --skip-chdir /` (no chroot syscall, only setuid/setgid). This assumes Railway grants root the default CAP_SETUID/CAP_SETGID capabilities.
- **Elasticsearch 8.19 with Temporal 1.32**: Temporal CI tests Elasticsearch 8 (8.5.0); 8.19 is expected to work but has not been tested here. Fallback: `ES_VERSION=v7` with an Elasticsearch 7.17 image, which is end-of-life.
- **Anonymous `monitor` role** on Elasticsearch exposes cluster metadata (index names, mappings, health) to other services in the same Railway project. It does not expose documents. Remove the anonymous settings and the healthcheck if this is unacceptable.
- **Shared Postgres connection budget**: Temporal caps at `SQL_MAX_CONNS=20`. Prisma sizes its pool from the host CPU count, which can be large on Railway hosts. If "too many connections" appears, lower `SQL_MAX_CONNS`, raise Postgres `max_connections`, or move Temporal to its own Postgres (add a second Postgres service and repoint `POSTGRES_SEEDS`, `DB_PORT`, `POSTGRES_USER`, `POSTGRES_PWD`).
- **Postgres 18**: upstream runs Postgres 16/17. Temporal's `postgres12` plugin and Prisma 6.5 are expected to work on 18 but have not been tested here.
- **Search-attribute cache**: attributes are registered right after Temporal starts, and Temporal refreshes its cache periodically. A post scheduled within the first minute of the very first boot could fail once; retrying works. Upstream's compose instead forces a cache refresh on every read, which Temporal labels dev-only.
- **Postiz runs `prisma db push --accept-data-loss` on every start**, and downloads Prisma via `pnpm dlx` at boot. This is upstream behaviour: it needs outbound npm access, and upgrades can drop columns. Back up Postgres before changing the Postiz tag.
- **Postiz healthcheck** targets the backend on port 3000 (Railway checks `PORT`), not nginx or the frontend on 5000.
- **Temporal UI internal port 8081** is reachable without auth from other services in the same project (private network), the same trust level as Temporal's gRPC port.
- **Elasticsearch licence**: the default distribution is under the Elastic License 2.0 (source also available under AGPL-3.0/SSPL). Self-hosting by the deployer is permitted. If Omtera plans to offer this stack as a managed service to third parties, take legal advice first.
- **`ELASTIC_PASSWORD` rotation**: the value is applied as the bootstrap password at start. If the `elastic` password is ever changed through the Elasticsearch API, the variable no longer applies. Keep both in sync manually.
