# AGENTS.md

This file is the source of truth for any AI agent working on PulseBoard.
Read this entire file before touching any code. Follow every rule here — do not
infer conventions from the existing code alone, as the code may be incomplete.

---

## What This Project Is

PulseBoard is a distributed real-time developer alerting and monitoring platform.
Developers register their backend services, define alert rules, and receive instant
notifications when thresholds are breached. Think of it as a self-hosted PagerDuty.

The backend is a **microservices architecture** — 7 independently deployable services
communicating over Kafka (async) and REST (sync). Every service lives under `services/`.

---

## Repo Structure

```
pulseboard/
├── AGENTS.md                    ← you are here
├── docker-compose.yml           ← spins up the full local stack
├── prometheus.yml               ← Prometheus scrape config
├── .env.example                 ← all required environment variables
├── .github/
│   └── workflows/
│       └── ci.yml               ← GitHub Actions pipeline
├── services/
│   ├── api-gateway/             ← Java, Spring Cloud Gateway, port 8080
│   ├── auth-service/            ← Java, Spring Boot, port 8081
│   ├── metrics-ingestion-service/ ← Java, Spring Boot, port 8082
│   ├── alert-engine-service/    ← Java, Spring Boot, port 8083
│   ├── notification-service/    ← Node.js, Express, port 8084
│   ├── analytics-service/       ← Java, Spring Boot, port 8085
│   └── health-poller-service/   ← Java, Spring Boot, port 8086
└── k8s/
    ├── deployments/
    └── services/
```

---

## Running the Project

### Start the full local stack
```bash
docker-compose up --build
```

### Start a single service (Java)
```bash
cd services/auth-service
./mvnw spring-boot:run
```

### Start a single service (Node.js)
```bash
cd services/notification-service
npm install
npm run dev
```

### Run all Java tests
```bash
cd services/auth-service
./mvnw test
```

### Run Node.js tests
```bash
cd services/notification-service
npm test
```

### Reset the full stack (wipe volumes)
```bash
docker-compose down -v
docker-compose up --build
```

---

## Non-Negotiable Rules

These are hard rules. Do not break them for any reason, including convenience,
speed, or because the existing code does it differently.

**Rule 1 — Never use `ddl-auto=create` or `ddl-auto=update`.**
All schema changes go through Flyway migrations in `src/main/resources/db/migration/`.
File naming: `V{number}__{description}.sql`. Example: `V3__add_alert_rules_table.sql`.

**Rule 2 — No secrets in code.**
All credentials, tokens, and keys come from environment variables. Use `${ENV_VAR}`
in `application.yml`. Never hardcode a password, JWT secret, or API key.

**Rule 3 — Every API endpoint needs an OpenAPI annotation.**
All controllers must have `@Tag`. All endpoints must have `@Operation` and at least
one `@ApiResponse`. Swagger UI must stay functional.

**Rule 4 — All services expose `/actuator/health` and `/actuator/prometheus`.**
Never disable Spring Actuator. The Prometheus scrape config depends on these endpoints.

**Rule 5 — Error responses follow one format, always.**
```json
{
  "error": "SNAKE_CASE_ERROR_CODE",
  "message": "Human readable explanation",
  "status": 404
}
```
Handle this in `GlobalExceptionHandler.java` with `@RestControllerAdvice`.
Never let a raw stack trace or Spring's default error page reach the client.

**Rule 6 — Business logic must have unit tests.**
Alert rule evaluation, JWT validation, rate limiting logic, and metric aggregation
are all business logic. They each need JUnit 5 tests. Do not skip tests to move faster.

**Rule 7 — Use structured JSON logging.**
All services use Logback with JSON output. Do not use `System.out.println`.
Use `log.info()`, `log.warn()`, `log.error()` with meaningful messages.

**Rule 8 — health-poller-service must use WebClient, not RestTemplate.**
The poller pings hundreds of endpoints concurrently. RestTemplate is blocking and
will exhaust the thread pool. WebClient is non-blocking and handles this correctly.

---

## Architecture Rules

These decisions are final. Do not propose alternatives unless explicitly asked.

**alert-engine-service has no database of its own.**
It reads alert rules from auth-service via REST (cached in Redis, TTL 60s).
It tracks alert state in Redis under the key `alert:state:{ruleId}`.
It writes alert history to MongoDB. It does not use JPA or PostgreSQL.

**All client traffic enters via api-gateway on port 8080.**
Services must not be called directly from a client in production. The gateway
handles JWT validation and rate limiting before any request reaches a service.

**notification-service is the only Node.js service.**
All other services are Java Spring Boot. Do not suggest rewriting services
in another language.

**Kafka is for async, REST is for sync.**
Use Kafka when the producer does not need an immediate response (metrics, alerts,
notifications). Use REST when a service needs data to complete a request (e.g.,
alert-engine fetching rules from auth-service).

---

## Service-by-Service Notes

### api-gateway (Java — Spring Cloud Gateway)
- Rate limiting uses `RequestRateLimiter` filter backed by Redis
- JWT validation happens in a `GatewayFilter`, not in downstream services
- Route config lives in `application.yml` under `spring.cloud.gateway.routes`
- Does not connect to any database

### auth-service (Java — Spring Boot)
- Owns PostgreSQL — all Flyway migrations live here
- Issues short-lived access tokens (15 min) and refresh tokens (7 days)
- Refresh tokens are stored in the `refresh_tokens` table, not in Redis
- OAuth2 success handler issues PulseBoard JWTs — does not rely on Google's session
- `@PreAuthorize` for ownership checks, never manual if-checks

### metrics-ingestion-service (Java — Spring Boot)
- Publishes each metric as a separate event to the `metrics.raw` Kafka topic
- Returns `202 ACCEPTED` immediately — never block on Kafka publish
- Stores raw metrics in MongoDB, not PostgreSQL
- Validates that the `serviceId` in the request belongs to the authenticated user

### alert-engine-service (Java — Spring Boot)
- Pure event-driven — no REST endpoints exposed
- Alert state machine: `OK → FIRING → OK`
- Once FIRING, do not re-fire until the alert resolves (deduplication via Redis)
- Saves every fired alert to MongoDB `alert_history` collection
- Publishes `AlertEvent` to `alerts.fired` and `alerts.resolved` Kafka topics

### notification-service (Node.js — Express)
- Consumes from `alerts.fired` and `alerts.resolved` Kafka topics using `kafkajs`
- Pushes real-time alerts via `socket.io` to `/alerts/{userId}`
- Sends emails via Nodemailer (Gmail SMTP)
- Logs every notification to MongoDB `notification_logs` collection
- Publishes audit events to `notifications.sent` Kafka topic

### health-poller-service (Java — Spring Boot)
- `@Scheduled` job runs every 30 seconds
- Fetches active services from auth-service via REST
- Pings each endpoint with a 5-second timeout using WebClient
- Runs pings in parallel — thread pool size 20
- Publishes results to `health.checks` Kafka topic as a metric event

### analytics-service (Java — Spring Boot)
- Consumes from `metrics.raw` and `alerts.fired` Kafka topics
- Stores aggregated data in MongoDB
- Exposes read-only REST endpoints — no write operations
- All endpoints require a valid JWT

---

## Kafka Topics

| Topic | Producer | Consumers |
|---|---|---|
| `metrics.raw` | metrics-ingestion-service | alert-engine-service, analytics-service |
| `alerts.fired` | alert-engine-service | notification-service |
| `alerts.resolved` | alert-engine-service | notification-service |
| `notifications.sent` | notification-service | analytics-service |
| `health.checks` | health-poller-service | metrics-ingestion-service |

---

## Database Ownership

| Database | Owner | What lives there |
|---|---|---|
| PostgreSQL | auth-service | users, refresh_tokens, monitored_services, alert_rules, notification_channels |
| MongoDB | metrics-ingestion-service | metrics_raw |
| MongoDB | alert-engine-service | alert_history |
| MongoDB | notification-service | notification_logs |
| MongoDB | analytics-service | aggregated_metrics |
| Redis | api-gateway | rate limit counters |
| Redis | auth-service | cached user/service/rule lookups |
| Redis | alert-engine-service | alert state per rule |

No service reads directly from another service's database.
Cross-service data access happens via REST calls only.

---

## Code Conventions

### Java
- Java 21, Spring Boot 3.x, Maven
- Package structure: `dev.pulseboard.{service}.{layer}`
  - Example: `dev.pulseboard.auth.controller`, `dev.pulseboard.auth.service`
- Use Lombok — `@Data`, `@Builder`, `@RequiredArgsConstructor`
- DTOs for all request and response bodies — never expose JPA entities directly
- Use `record` for immutable request/response types where appropriate
- Service layer holds business logic, controller layer holds only HTTP concerns

### Node.js (notification-service only)
- Node.js 20 LTS, Express 4.x
- Use ES modules (`"type": "module"` in `package.json`)
- Use `async/await` — no raw `.then()` chains
- Use `winston` for structured JSON logging
- Environment variables via `dotenv` in development only

### Git
- Branch naming: `feature/{service-name}/{short-description}`
  - Example: `feature/auth-service/refresh-token-rotation`
- Commit messages follow Conventional Commits:
  - `feat(auth): add refresh token rotation`
  - `fix(alert-engine): deduplicate firing state on restart`
  - `chore(docker): add analytics-service to compose`
- Never commit directly to `main`

---

## Environment Variables

All variables are defined in `.env.example` at the project root.
Copy to `.env` before running locally. Never commit `.env`.

Key variables:

```
# Database
POSTGRES_USER=
POSTGRES_PASSWORD=
MONGO_USER=
MONGO_PASSWORD=

# Auth
JWT_SECRET=                    # min 256-bit random string
JWT_EXPIRY_MS=900000           # 15 minutes
JWT_REFRESH_EXPIRY_MS=604800000 # 7 days

# OAuth2
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# Mail (notification-service)
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=                 # Gmail app password, not account password

# Observability
OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4317
```

---

## What to Do When Stuck

1. Check this file first — the answer is usually here.
2. Check the service's own `README.md` for service-specific notes.
3. Check `docker-compose.yml` for how services connect to infrastructure.
4. If a Flyway migration fails, do not delete it. Create a new migration to fix it.
5. If a Kafka consumer stops receiving messages, check the consumer group ID —
   two services sharing a group ID will split messages between them unintentionally.

---

## What Not to Do

- Do not add new dependencies without a documented reason in the PR description.
- Do not bypass the API gateway and call services directly.
- Do not store passwords, tokens, or keys anywhere in the codebase.
- Do not write a new Flyway migration that modifies or deletes an existing one.
- Do not add `@SuppressWarnings` to hide compiler warnings — fix the root cause.
- Do not return HTTP 200 for errors. Use the correct status code every time.
- Do not merge code with failing tests. Fix the tests or fix the code.