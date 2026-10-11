# Deploy and Host Postiz with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/postiz-v2-ai-social-media-scheduler?referralCode=20H68q)

Postiz is an open-source social media scheduler. It plans, schedules and publishes posts to X, LinkedIn, Instagram, Facebook, Threads, YouTube, TikTok, Bluesky, Mastodon and other networks, with optional AI writing help. This community template deploys Postiz v2 on Railway with the full stack it needs, including the Temporal workflow engine.

## About Hosting Postiz

Postiz v2 is more than a web app with a database. Since v2.12.0 every scheduled post runs as a durable Temporal workflow, so a self-hosted install needs a Temporal server, its persistence, and a visibility store that Postiz queries when posts are edited or deleted. This template runs all of it: the Postiz container (frontend, API and Temporal workers), PostgreSQL, Redis, a single-node Temporal server, Elasticsearch for Temporal visibility, and the Temporal Web UI behind a password. Services talk over Railway's private network. Uploaded media is stored on a volume and served from your Postiz domain, so social networks can fetch it.

## Common Use Cases

- Plan and schedule a content calendar across several social networks from one dashboard
- Let a small marketing team or agency collaborate on posts with an owner-controlled, self-hosted instance
- Keep social media credentials, drafts and analytics on infrastructure you control
- Draft and refine posts with an AI assistant using your own OpenAI key
- Automate posting through the Postiz public API from other tools or workflows

## Dependencies for Postiz Hosting

- PostgreSQL (Postiz data and, in a separate database, Temporal persistence)
- Redis (caching and rate limiting)
- Temporal server (workflow engine that runs scheduling and publishing)
- Elasticsearch (Temporal visibility store for workflow search)
- A persistent volume for uploaded media
- Developer app credentials for each social network you want to connect (optional at deploy time)

### Deployment Dependencies

- Postiz source and releases: https://github.com/gitroomhq/postiz-app
- Postiz self-hosting docs: https://docs.postiz.com
- Postiz configuration reference: https://docs.postiz.com/configuration/reference
- Postiz docker-compose reference: https://github.com/gitroomhq/postiz-docker-compose
- Temporal server: https://github.com/temporalio/temporal
- Temporal visibility and Elasticsearch: https://docs.temporal.io/self-hosted-guide/visibility
- Temporal Web UI: https://github.com/temporalio/ui
- Elasticsearch Docker image: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/docker.html

### Implementation Details

| Service | Image | Purpose | Public |
|---|---|---|---|
| Postiz | `ghcr.io/gitroomhq/postiz-app:v2.25.0` | Web app, API and Temporal workers (nginx on port 5000); media volume at `/uploads` | Yes |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Databases `railway` (Postiz) and `temporal` (Temporal) | No |
| Redis | `redis:8.2` | Cache and rate limiting | No |
| Temporal | `temporalio/server:1.32.1` (+ admin tools) | Workflow engine; creates and upgrades its schema, namespace and search attributes on every boot | No |
| Elasticsearch | `elasticsearch:8.19.23` (official) | Temporal visibility index; password protected | No |
| Temporal UI | `temporalio/ui:2.55.0` + Caddy | Workflow inspection behind basic auth | Yes |

**First login**
1. Wait until all services are healthy. On the first deploy Temporal waits for Elasticsearch and Postgres, so Postiz can take several minutes to pass its healthcheck.
2. Open the Postiz domain and register right away. The first account becomes the owner. Registration then closes automatically (`DISABLE_REGISTRATION=true`).
3. To invite teammates who need new accounts, set `DISABLE_REGISTRATION=false` on the Postiz service, let them sign up, then set it back to `true`.
4. No email service is required. Accounts are activated automatically while `EMAIL_PROVIDER` is empty. Set `EMAIL_PROVIDER=resend` with `RESEND_API_KEY`, or `nodemailer` with SMTP settings, if you want activation and notification emails.
5. To connect a network, create a developer app with that network and use the redirect URI `https://{your-postiz-domain}/integrations/social/{provider}`. Then add its keys (for example `X_API_KEY`/`X_API_SECRET` or `LINKEDIN_CLIENT_ID`/`LINKEDIN_CLIENT_SECRET`) to the Postiz service. Bluesky only needs a handle and an app password.
6. Temporal UI credentials are the `TEMPORAL_UI_USERNAME` and `TEMPORAL_UI_PASSWORD` variables on the Temporal UI service.
7. If you add a custom domain to Postiz, update `MAIN_URL`, `FRONTEND_URL` and `NEXT_PUBLIC_BACKEND_URL`, plus the redirect URIs in your social apps.

**Scaling**
- Postiz runs its web app and its Temporal workers in one container with a media volume, so it scales vertically: raise its CPU/RAM limits. Volumes rule out replicas.
- Temporal runs as a single node. `NUM_HISTORY_SHARDS` is fixed at the first boot.
- Elasticsearch memory is set by `ES_JAVA_OPTS`. Raise the heap together with the service's RAM if visibility queries slow down.

**Pinning and upgrading**
- Postiz: change the image tag on the Postiz service (for example `v2.25.0` to a newer `v2.x`). Back up Postgres first, because Postiz applies schema changes with `prisma db push` on start.
- Temporal: change both `FROM` tags in `services/temporal/Dockerfile`, one minor version at a time. The entrypoint applies database and index schema upgrades on the next boot.
- Elasticsearch and Temporal UI: change the tag in their Dockerfiles. Stay on the 8.x line for Elasticsearch unless Temporal documents support for a newer major.
- Postgres and Redis follow the Railway base images.

### Why Deploy Postiz on Railway?

Postiz needs half a dozen cooperating services. Railway runs them as one project with private networking, generated secrets, persistent volumes and HTTPS domains. You get a working scheduler without managing servers, and you can still change every variable, pin versions and see each service's logs and metrics. This is a community template and is not affiliated with Postiz, Temporal or Elastic.
