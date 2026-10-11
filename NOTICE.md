# Notice

## Upstream software

| Component | License | Image used | Publisher |
|---|---|---|---|
| Postiz | AGPL-3.0 | `ghcr.io/gitroomhq/postiz-app:v2.25.0` | Gitroom (gitroomhq) |
| Temporal server and admin tools | MIT | `temporalio/server:1.32.1`, `temporalio/admin-tools:1.32.1` (binaries and schema files copied into the Temporal image) | Temporal Technologies Inc. |
| Temporal Web UI | MIT | `temporalio/ui:2.55.0` | Temporal Technologies Inc. |
| Caddy | Apache-2.0 | `caddy:2.11.7-alpine` (binary copied into the Temporal UI image) | Caddy project / Docker Official Images |
| Elasticsearch | Default distribution under the Elastic License 2.0 (source also available under AGPL-3.0 and SSPL) | `docker.elastic.co/elasticsearch/elasticsearch:8.19.23` | Elasticsearch B.V. |
| PostgreSQL (Railway image) | PostgreSQL License; image repo MIT | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Railway |
| Redis | Redis 8: RSALv2 / SSPLv1 / AGPLv3 | `redis:8.2` | Redis Ltd. / Docker Official Images |

The images are pulled unmodified from their publishers. The three repo-based services add only the configuration and scripts in `services/` on top of those images.

## Verified against

All checked on 2026-10-10.

- Postiz release `v2.25.0` (published 2026-10-02): `gh api repos/gitroomhq/postiz-app/releases/latest`; image tag confirmed on GHCR (manifest `ghcr.io/gitroomhq/postiz-app:v2.25.0` → 200).
- Postiz source at tag `v2.25.0` (https://github.com/gitroomhq/postiz-app/tree/v2.25.0):
  - `Dockerfile.dev` (the file `.github/workflows/build-containers.yml` builds the GHCR image from) and `var/docker/nginx.conf`: nginx on 5000, `/api/` → backend :3000, `/uploads/` alias, frontend :4200
  - `package.json`, `apps/*/package.json`: pm2 processes, `prisma db push` on start, Prisma 6.5.0
  - `apps/backend/src/main.ts`: backend port `PORT || 3000`; `NOT_SECURED` truthiness check
  - `apps/backend/src/services/auth/auth.service.ts`, `apps/backend/src/api/routes/auth.controller.ts`, `apps/frontend/src/app/(app)/auth/page.tsx`: `DISABLE_REGISTRATION` allows the first sign-up; `/auth/can-register`
  - `libraries/nestjs-libraries/src/temporal/*`: `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, search attributes `organizationId`/`postId` (Text), `RUN_CRON` workflow
  - `libraries/nestjs-libraries/src/database/prisma/posts/posts.service.ts`: visibility query `postId="…" AND ExecutionStatus="Running"`
  - `libraries/nestjs-libraries/src/upload/upload.factory.ts`, `cloudflare.storage.ts`, `local.storage.ts`: storage providers `local`/`cloudflare`, R2 endpoint hard-coded
  - `libraries/nestjs-libraries/src/redis/redis.service.ts`: ioredis client
  - `libraries/nestjs-libraries/src/services/email.service.ts`: email provider selection
  - `.env.example`: variable names
- Postiz docker-compose `docker-compose.yaml` and `dynamicconfig/development-sql.yaml` at `main` commit `dd4969e5e6` (2026-07-30): https://github.com/gitroomhq/postiz-docker-compose
- Postiz configuration reference: https://docs.postiz.com/configuration/reference (Temporal required since v2.12.0; `NOT_SECURED` dev-only; storage options)
- Temporal `v1.32.1` (published 2026-10-08), https://github.com/temporalio/temporal/tree/v1.32.1:
  - `docker/targets/server.Dockerfile`, `docker/targets/admin-tools.Dockerfile`, `docker/scripts/sh/entrypoint.sh`
  - `common/config/config_template_embedded.yaml` (server environment variables)
  - `common/dynamicconfig/file_based_client.go`, `temporal/fx.go` (dynamic config file required)
  - `cmd/server/main.go`, `common/config/loader.go` (`TEMPORAL_ALLOW_NO_AUTH`)
  - `tools/sql/*`, `tools/common/schema/setuptask.go`, `common/persistence/sql/sqlplugin/postgresql/*` (idempotent create/setup/update)
  - `tools/elasticsearch/*` (setup-schema, create-index, update-schema)
  - `common/persistence/visibility/store/elasticsearch/client/client_factory.go` (v7/v8 support), `common/persistence/visibility/store/query/converter.go` (Text supports `=`/`!=`)
  - `common/rpc/rpc.go` (IPv6 `bindOnIP`), `develop/github/docker-compose.yml` (CI uses Elasticsearch 8)
  - Release notes v1.31.0 / v1.32.0 (schema and visibility changes)
- Temporal reference compose (replacement for the archived `temporalio/docker-compose`): https://github.com/temporalio/samples-server/tree/main/compose, commit `dd5a3b5e88` (2026-10-07)
- Temporal visibility docs: https://docs.temporal.io/self-hosted-guide/visibility
- Temporal UI `v2.55.0`: `server/Dockerfile`, `server/docker/start-ui-server.sh`, `server/config/docker.yaml` at https://github.com/temporalio/ui/tree/v2.55.0
- Elasticsearch `v8.19.23`: `distribution/docker/src/docker/Dockerfile`, `distribution/docker/src/docker/bin/docker-entrypoint.sh`, `build-tools-internal/.../DockerBase.java` (default base `ubuntu:24.04`) at https://github.com/elastic/elasticsearch/tree/v8.19.23; network settings https://www.elastic.co/guide/en/elasticsearch/reference/8.19/modules-network.html; end-of-life dates https://endoflife.date/elasticsearch
- Docker Hub tag API for `temporalio/server:1.32.1`, `temporalio/admin-tools:1.32.1`, `temporalio/ui:2.55.0`, `caddy:2.11.7-alpine`, `elasticsearch:8.19.23`; `temporalio/auto-setup` tag list (latest 1.29.7)
- Railway healthchecks: https://docs.railway.com/guides/healthchecks; ioredis `family=0`: https://docs.railway.com/networking/private-networking/library-configuration

## Adapted code

- **temporalio/samples-server** — `compose/scripts/setup-postgres-es.sh` and `compose/scripts/create-namespace.sh`. Copyright (c) 2020 Temporal Technologies Inc. MIT License.
  `services/temporal/railway-entrypoint.sh` follows the same command sequence (`temporal-sql-tool create / setup-schema -v 0.0 / update-schema`, `temporal-elasticsearch-tool setup-schema / create-index`, `temporal operator namespace describe/create`). The script was written for this template: it adds retries for parallel start on Railway, `update-schema` for the index, search-attribute registration, single-container server supervision and Elasticsearch credentials. No text was copied verbatim.
- All other files in `services/` (Dockerfiles, `elasticsearch.yml`, `roles.yml`, Elasticsearch entrypoint, `Caddyfile`, Temporal UI `start.sh`, `dynamicconfig/railway.yaml`) were written for this template from the official documentation and image sources listed above.

## Reference only (not copied)

- `Shinyduo/elasticsearch-railway` (`_upstream/Shinyduo__elasticsearch-railway`, deployed by the `postiz` market template): no license. Read for ideas only; no files or text copied.
- Railway market templates `postiz`, `deploy-postiz` and `Rd76MM` (`_market/*.json`): read for configuration ideas only; no README text copied.
- `gitroomhq/postiz-docker-compose` (AGPL-3.0): used as the reference for services and variable names; no files copied.

## Trademarks

Postiz is a trademark of its owner. Temporal is a trademark of Temporal Technologies Inc. Elasticsearch and Elastic are trademarks of Elasticsearch B.V. Redis is a trademark of Redis Ltd. PostgreSQL is a trademark of the PostgreSQL Community Association. Caddy is a trademark of its owner. This is a community template; it is not affiliated with or endorsed by any of these owners.
