# PulseBoard — GitHub Issues (Detailed)

## How to use this file

Paste this to your AI agent (Copilot Agent Mode / Claude Code) with the GitHub MCP connected.

**Agent instructions:**
1. Create labels and milestones first (listed below)
2. Create issues ONE MILESTONE AT A TIME
3. Wait for my confirmation before moving to the next milestone
4. Every issue references other issues by number — use those numbers exactly as GitHub links

---

## Labels to create first

| Name | Color | Description |
|---|---|---|
| `setup` | #1D9E75 | Project bootstrapping and initial config |
| `feature` | #7F77DD | New functionality |
| `test` | #EF9F27 | Unit or integration tests |
| `infra` | #378ADD | Docker, CI/CD, Kubernetes |
| `chore` | #888780 | Non-feature work — docs, cleanup, verification |

## Milestones to create first

| Name | Description |
|---|---|
| `M1 — Infrastructure` | Docker Compose, env setup, Prometheus config |
| `M2 — auth-service` | Users, JWT, OAuth2, service + rule CRUD |
| `M3 — api-gateway` | Routing, rate limiting, JWT filter |
| `M4 — metrics-ingestion-service` | Ingest metrics, publish to Kafka, store in MongoDB |
| `M5 — alert-engine-service` | Evaluate rules, manage alert state, fire alerts |
| `M6 — health-poller-service` | Ping endpoints every 30s, publish results |

---

---

# MILESTONE 1 — Infrastructure & Project Setup

---

## Issue #01 — Create monorepo folder structure

**Labels:** chore
**Milestone:** M1 — Infrastructure
**Depends on:** nothing — this is the very first issue

---

**Context**

Before any code is written, the repository needs a consistent folder structure. Every service lives under `services/`. This structure is what the `docker-compose.yml` (Issue #02) and GitHub Actions CI (later) will rely on.

---

**Folder structure to create:**

```
pulseboard/
├── AGENTS.md
├── .env.example              ← created in Issue #03
├── docker-compose.yml        ← created in Issue #02
├── prometheus.yml            ← created in Issue #04
├── .gitignore
├── .github/
│   └── workflows/
│       └── ci.yml            ← placeholder for now
└── services/
    ├── api-gateway/
    │   └── README.md
    ├── auth-service/
    │   └── README.md
    ├── metrics-ingestion-service/
    │   └── README.md
    ├── alert-engine-service/
    │   └── README.md
    ├── notification-service/
    │   └── README.md
    ├── analytics-service/
    │   └── README.md
    └── health-poller-service/
        └── README.md
```

**`.gitignore` must cover:**
- Java: `target/`, `*.class`, `.idea/`, `*.iml`
- Node.js: `node_modules/`, `dist/`
- Environment: `.env`, `*.env`
- OS: `.DS_Store`, `Thumbs.db`

Each `README.md` placeholder should contain just the service name and its port for now.

---

**Acceptance criteria:**
- [ ] All folders exist as shown above
- [ ] `.gitignore` prevents committing `.env`, `target/`, `node_modules/`
- [ ] `git status` is clean after creating this structure
- [ ] Opened the way for Issue #02 (docker-compose) and Issue #06 (auth-service bootstrap)

---

## Issue #02 — Write docker-compose.yml

**Labels:** infra
**Milestone:** M1 — Infrastructure
**Depends on:** #01 (folder structure must exist)
**Required by:** every subsequent issue — this is the backbone of local development

---

**Context**

Every developer (and the AI agent) runs the full PulseBoard stack locally with a single command: `docker-compose up`. This file defines all the infrastructure services. The application services (auth-service, gateway, etc.) will be added to this file as they are built in later milestones. For now, only infrastructure.

All credentials must come from environment variables defined in `.env` (see Issue #03). Never hardcode passwords here.

---

**File to create:** `docker-compose.yml` at project root

**Full content:**

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16
    container_name: pulseboard-postgres
    environment:
      POSTGRES_DB: pulsedb
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d pulsedb"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: pulseboard-redis
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: pulseboard-zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    container_name: pulseboard-kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092,PLAINTEXT_INTERNAL://kafka:29092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_INTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT_INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions", "--bootstrap-server", "localhost:9092"]
      interval: 15s
      timeout: 10s
      retries: 10

  mongodb:
    image: mongo:7
    container_name: pulseboard-mongodb
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
      MONGO_INITDB_DATABASE: pulsedb
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: pulseboard-jaeger
    ports:
      - "16686:16686"   # Jaeger UI
      - "4317:4317"     # OTLP gRPC
      - "4318:4318"     # OTLP HTTP

  prometheus:
    image: prom/prometheus:latest
    container_name: pulseboard-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'

  grafana:
    image: grafana/grafana:latest
    container_name: pulseboard-grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
    volumes:
      - grafana_data:/var/lib/grafana

volumes:
  postgres_data:
  mongo_data:
  grafana_data:
```

---

**Acceptance criteria:**
- [ ] `docker-compose up` starts all 8 infrastructure services without errors
- [ ] PostgreSQL health check passes: `docker exec pulseboard-postgres pg_isready`
- [ ] Redis health check passes: `docker exec pulseboard-redis redis-cli ping` returns `PONG`
- [ ] Kafka is reachable on port 9092
- [ ] Jaeger UI opens at `http://localhost:16686`
- [ ] Prometheus UI opens at `http://localhost:9090`
- [ ] Grafana UI opens at `http://localhost:3000`
- [ ] No credentials hardcoded — all come from `.env`

---

## Issue #03 — Create .env.example

**Labels:** chore
**Milestone:** M1 — Infrastructure
**Depends on:** #01 (folder structure)
**Required by:** #02 (docker-compose reads from .env), all services

---

**Context**

`.env.example` documents every environment variable used across the entire project. Developers copy it to `.env` and fill in real values. The `.env` file is gitignored (see Issue #01). Never commit real credentials.

---

**File to create:** `.env.example` at project root

```bash
# ─────────────────────────────────────────
# PostgreSQL (used by auth-service)
# ─────────────────────────────────────────
POSTGRES_USER=pulseuser
POSTGRES_PASSWORD=changeme_postgres
POSTGRES_URL=jdbc:postgresql://localhost:5432/pulsedb

# ─────────────────────────────────────────
# MongoDB (used by metrics-ingestion, alert-engine, notification, analytics)
# ─────────────────────────────────────────
MONGO_USER=mongouser
MONGO_PASSWORD=changeme_mongo
MONGO_URI=mongodb://mongouser:changeme_mongo@localhost:27017/pulsedb?authSource=admin

# ─────────────────────────────────────────
# Redis (used by api-gateway rate limiter, auth-service cache, alert-engine state)
# ─────────────────────────────────────────
REDIS_HOST=localhost
REDIS_PORT=6379

# ─────────────────────────────────────────
# Kafka (used by metrics-ingestion, alert-engine, health-poller, notification)
# ─────────────────────────────────────────
KAFKA_BOOTSTRAP_SERVERS=localhost:9092

# ─────────────────────────────────────────
# JWT (used by auth-service and api-gateway)
# Must be a random string of at least 64 characters
# Generate with: openssl rand -hex 64
# ─────────────────────────────────────────
JWT_SECRET=replace_with_64_char_random_string
JWT_EXPIRY_MS=900000
JWT_REFRESH_EXPIRY_MS=604800000

# ─────────────────────────────────────────
# Google OAuth2 (used by auth-service)
# Get from: https://console.cloud.google.com/
# ─────────────────────────────────────────
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# ─────────────────────────────────────────
# Mail / Notifications (used by notification-service)
# Use a Gmail App Password, not your account password
# ─────────────────────────────────────────
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your_email@gmail.com
MAIL_PASSWORD=your_gmail_app_password

# ─────────────────────────────────────────
# Observability
# ─────────────────────────────────────────
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
GRAFANA_PASSWORD=admin
```

---

**Acceptance criteria:**
- [ ] Every variable used in `docker-compose.yml` (Issue #02) is present here
- [ ] Every variable used in any service's `application.yml` is present here
- [ ] Comments explain what each variable does and where to get its value
- [ ] `.env` (real values) is listed in `.gitignore` and never committed

---

## Issue #04 — Create prometheus.yml

**Labels:** infra
**Milestone:** M1 — Infrastructure
**Depends on:** #01 (folder structure)
**Required by:** #02 (docker-compose mounts this file)

---

**Context**

Prometheus scrapes metrics from every Spring Boot service via their `/actuator/prometheus` endpoint (exposed by Micrometer). This file tells Prometheus where each service lives and how often to scrape. Services don't exist yet — Prometheus will show them as DOWN until each service is built and running.

---

**File to create:** `prometheus.yml` at project root

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'auth-service'
    static_configs:
      - targets: ['host.docker.internal:8081']
    metrics_path: '/actuator/prometheus'

  - job_name: 'api-gateway'
    static_configs:
      - targets: ['host.docker.internal:8080']
    metrics_path: '/actuator/prometheus'

  - job_name: 'metrics-ingestion-service'
    static_configs:
      - targets: ['host.docker.internal:8082']
    metrics_path: '/actuator/prometheus'

  - job_name: 'alert-engine-service'
    static_configs:
      - targets: ['host.docker.internal:8083']
    metrics_path: '/actuator/prometheus'

  - job_name: 'notification-service'
    static_configs:
      - targets: ['host.docker.internal:8084']
    metrics_path: '/actuator/prometheus'

  - job_name: 'analytics-service'
    static_configs:
      - targets: ['host.docker.internal:8085']
    metrics_path: '/actuator/prometheus'

  - job_name: 'health-poller-service'
    static_configs:
      - targets: ['host.docker.internal:8086']
    metrics_path: '/actuator/prometheus'
```

> **Note:** `host.docker.internal` lets the Prometheus container reach services running on the host machine. On Linux, add `--add-host=host.docker.internal:host-gateway` to the Prometheus container in docker-compose.yml.

---

**Acceptance criteria:**
- [ ] File exists and is valid YAML
- [ ] `docker-compose up` mounts it without errors
- [ ] Prometheus UI at `http://localhost:9090/targets` shows all 7 targets (DOWN is fine — services not built yet)

---

## Issue #05 — Verify Milestone 1 is complete

**Labels:** chore
**Milestone:** M1 — Infrastructure
**Depends on:** #01, #02, #03, #04

---

**Context**

Manual verification checkpoint before starting any application code. Everything in Milestone 2 (auth-service) depends on PostgreSQL, Redis, and Kafka being healthy. Do not proceed to Milestone 2 until all checks below pass.

---

**Checklist:**
- [ ] `docker-compose up` starts cleanly with no fatal errors
- [ ] `docker ps` shows all 8 containers running
- [ ] PostgreSQL: `docker exec pulseboard-postgres pg_isready -U pulseuser` → `accepting connections`
- [ ] Redis: `docker exec pulseboard-redis redis-cli ping` → `PONG`
- [ ] Kafka: `docker exec pulseboard-kafka kafka-topics --list --bootstrap-server localhost:9092` → no error
- [ ] MongoDB: `docker exec pulseboard-mongodb mongosh --eval "db.adminCommand('ping')"` → `{ ok: 1 }`
- [ ] Jaeger UI: `http://localhost:16686` loads
- [ ] Prometheus: `http://localhost:9090/targets` shows 7 targets (all DOWN — expected)
- [ ] Grafana: `http://localhost:3000` loads and login works with admin / $GRAFANA_PASSWORD
- [ ] `.env` is NOT tracked by git: `git status` does not show `.env`

---

---

# MILESTONE 2 — auth-service

---

## Issue #06 — Bootstrap auth-service

**Labels:** setup
**Milestone:** M2 — auth-service
**Depends on:** #05 (infrastructure must be running)
**Required by:** every other issue in M2, and Issue #28 (gateway routes)

---

**Context**

auth-service is the most foundational service in PulseBoard. It owns:
- The PostgreSQL database (all Flyway migrations live here)
- User registration and login
- JWT token issuance and validation
- OAuth2 Google login
- Monitored service and alert rule management

Every other service trusts tokens issued by auth-service.

---

**Create the project at:** `services/auth-service/`

Generate with Spring Initializr (`https://start.spring.io`) or via the Spring Boot CLI.

**Group:** `dev.pulseboard`
**Artifact:** `auth-service`
**Java:** 21
**Build:** Maven
**Spring Boot:** 3.x (latest stable)

**Dependencies (pom.xml):**
```xml
<dependencies>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-security</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-oauth2-client</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-validation</artifactId></dependency>
  <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId></dependency>
  <dependency><groupId>org.flywaydb</groupId><artifactId>flyway-core</artifactId></dependency>
  <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></dependency>
  <dependency><groupId>org.springdoc</groupId><artifactId>springdoc-openapi-starter-webmvc-ui</artifactId><version>2.3.0</version></dependency>
  <dependency><groupId>io.jsonwebtoken</groupId><artifactId>jjwt-api</artifactId><version>0.12.3</version></dependency>
  <dependency><groupId>io.jsonwebtoken</groupId><artifactId>jjwt-impl</artifactId><version>0.12.3</version><scope>runtime</scope></dependency>
  <dependency><groupId>io.jsonwebtoken</groupId><artifactId>jjwt-jackson</artifactId><version>0.12.3</version><scope>runtime</scope></dependency>
  <dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId></dependency>
</dependencies>
```

**`application.yml` to create:**
```yaml
server:
  port: 8081

spring:
  application:
    name: auth-service
  datasource:
    url: ${POSTGRES_URL}
    username: ${POSTGRES_USER}
    password: ${POSTGRES_PASSWORD}
    driver-class-name: org.postgresql.Driver
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
  flyway:
    enabled: true
    locations: classpath:db/migration
  data:
    redis:
      host: ${REDIS_HOST}
      port: ${REDIS_PORT}

jwt:
  secret: ${JWT_SECRET}
  expiry-ms: ${JWT_EXPIRY_MS}
  refresh-expiry-ms: ${JWT_REFRESH_EXPIRY_MS}

management:
  endpoints:
    web:
      exposure:
        include: health,prometheus,metrics
  endpoint:
    health:
      show-details: always

springdoc:
  api-docs:
    path: /v3/api-docs
  swagger-ui:
    path: /swagger-ui.html
```

**Main class must have:**
```java
@SpringBootApplication
@EnableCaching
public class AuthServiceApplication {
  public static void main(String[] args) {
    SpringApplication.run(AuthServiceApplication.class, args);
  }
}
```

---

**Acceptance criteria:**
- [ ] Application starts on port 8081 with `./mvnw spring-boot:run`
- [ ] `/actuator/health` returns `{"status":"UP"}`
- [ ] `/actuator/prometheus` returns Prometheus metrics
- [ ] Swagger UI loads at `http://localhost:8081/swagger-ui.html`
- [ ] No compile errors

---

## Issue #07 — Configure PostgreSQL and Flyway

**Labels:** setup
**Milestone:** M2 — auth-service
**Depends on:** #06 (auth-service bootstrapped), #05 (PostgreSQL running)
**Required by:** #08 through #12 (all Flyway migrations)

---

**Context**

Flyway manages all database schema changes through versioned SQL migration files. The file naming convention is strict: `V{version}__{description}.sql` (note the double underscore). Flyway runs migrations automatically at startup, in order. Never modify an existing migration file — always create a new one to fix it.

`ddl-auto: validate` means Spring will verify the DB schema matches the JPA entities. If they don't match, the app refuses to start. This prevents silent schema drift.

---

**Create directory:** `services/auth-service/src/main/resources/db/migration/`

**Verify `application.yml` (already set in #06) has:**
```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate   # NEVER use create or update
  flyway:
    enabled: true
    locations: classpath:db/migration
```

**Add a `application-test.yml` for tests:**
```yaml
spring:
  flyway:
    enabled: true
  jpa:
    hibernate:
      ddl-auto: validate
  datasource:
    url: jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1
    driver-class-name: org.h2.Driver
```

Add H2 test dependency to `pom.xml`:
```xml
<dependency>
  <groupId>com.h2database</groupId>
  <artifactId>h2</artifactId>
  <scope>test</scope>
</dependency>
```

---

**Acceptance criteria:**
- [ ] Application starts cleanly — Flyway logs `Successfully applied 0 migrations`
- [ ] `flyway_schema_history` table exists in PostgreSQL after startup
- [ ] Adding a random character to an entity field causes startup failure with a clear validation error (proves `ddl-auto: validate` works)

---

## Issue #08 — V1 migration: create users table

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #07 (Flyway configured)
**Required by:** #13 (User entity), #14 (register), #17 (login), #20 (OAuth2)

---

**Context**

The `users` table is the foundation of all other tables. Every other entity has a foreign key back to users. The `provider` column supports both email/password login (`LOCAL`) and OAuth2 (`GOOGLE`). OAuth users will not have a `password_hash`.

---

**File to create:** `src/main/resources/db/migration/V1__create_users_table.sql`

```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE users (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email            VARCHAR(255) UNIQUE NOT NULL,
    password_hash    VARCHAR(255),
    name             VARCHAR(255) NOT NULL,
    provider         VARCHAR(50)  NOT NULL DEFAULT 'LOCAL',
    provider_id      VARCHAR(255),
    role             VARCHAR(50)  NOT NULL DEFAULT 'USER',
    created_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);

COMMENT ON COLUMN users.provider IS 'LOCAL or GOOGLE';
COMMENT ON COLUMN users.provider_id IS 'Google sub claim, null for LOCAL users';
COMMENT ON COLUMN users.password_hash IS 'BCrypt hash, null for OAuth users';
```

---

**Acceptance criteria:**
- [ ] Flyway applies this migration on startup
- [ ] `\d users` in psql shows all 9 columns with correct types
- [ ] `email` column has a unique constraint
- [ ] `id` column generates a UUID automatically

---

## Issue #09 — V2 migration: create refresh_tokens table

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #08 (users table must exist first — foreign key)
**Required by:** #17 (login saves refresh token), #18 (refresh endpoint reads it), #19 (logout deletes it)

---

**Context**

Refresh tokens are stored in the database, not in Redis or in-memory. This means they survive service restarts and can be revoked by deleting the row. The `expires_at` column allows the app to reject tokens that are structurally valid (correct signature) but have been revoked by time.

---

**File to create:** `src/main/resources/db/migration/V2__create_refresh_tokens_table.sql`

```sql
CREATE TABLE refresh_tokens (
    id           UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token        TEXT      UNIQUE NOT NULL,
    expires_at   TIMESTAMP NOT NULL,
    created_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_token ON refresh_tokens(token);
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
```

---

**Acceptance criteria:**
- [ ] Migration applies cleanly after V1
- [ ] Foreign key to `users.id` with `ON DELETE CASCADE` — deleting a user deletes their tokens
- [ ] `token` column is unique and indexed for fast lookups

---

## Issue #10 — V3 migration: create monitored_services table

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #08 (users table must exist)
**Required by:** #21 (MonitoredService CRUD), #46 (health-poller fetches services), #33 (metrics ingest validates ownership)

---

**Context**

A monitored service is any backend service a PulseBoard user registers for monitoring. The `endpoint_url` is what the health-poller will ping (Issue #47). The `owner_id` links to the user — only the owner can modify or delete it.

---

**File to create:** `src/main/resources/db/migration/V3__create_monitored_services_table.sql`

```sql
CREATE TABLE monitored_services (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name         VARCHAR(255) NOT NULL,
    endpoint_url TEXT         NOT NULL,
    description  TEXT,
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_monitored_services_owner ON monitored_services(owner_id);
CREATE INDEX idx_monitored_services_active ON monitored_services(is_active);
```

---

**Acceptance criteria:**
- [ ] Migration applies after V2
- [ ] `owner_id` is a foreign key to `users(id)` with `ON DELETE CASCADE`
- [ ] `is_active` defaults to `TRUE`

---

## Issue #11 — V4 migration: create alert_rules table

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #10 (monitored_services must exist)
**Required by:** #22 (AlertRule CRUD), #38 (alert-engine evaluates these rules)

---

**Context**

Each alert rule belongs to a service and defines a condition: "if `cpu_usage > 80` for 60 seconds, fire a CRITICAL alert." The `operator` column stores `>`, `<`, `>=`, `<=`, or `==`. The `metric_name` must exactly match the metric names sent by the metrics-ingestion-service (Issue #33).

---

**File to create:** `src/main/resources/db/migration/V4__create_alert_rules_table.sql`

```sql
CREATE TABLE alert_rules (
    id               UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id       UUID             NOT NULL REFERENCES monitored_services(id) ON DELETE CASCADE,
    metric_name      VARCHAR(100)     NOT NULL,
    operator         VARCHAR(10)      NOT NULL,
    threshold        DOUBLE PRECISION NOT NULL,
    duration_seconds INT              NOT NULL DEFAULT 60,
    severity         VARCHAR(20)      NOT NULL DEFAULT 'WARNING',
    is_active        BOOLEAN          NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP        NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_operator CHECK (operator IN ('>', '<', '>=', '<=', '==')),
    CONSTRAINT chk_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL'))
);

CREATE INDEX idx_alert_rules_service ON alert_rules(service_id);
CREATE INDEX idx_alert_rules_active ON alert_rules(is_active);
```

---

**Acceptance criteria:**
- [ ] `operator` column has a CHECK constraint — invalid operators are rejected at the DB level
- [ ] `severity` column has a CHECK constraint
- [ ] Migration applies after V3

---

## Issue #12 — V5 migration: create notification_channels table

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #08 (users table must exist)
**Required by:** notification-service (later milestone) reads channel config from here

---

**Context**

A notification channel is how PulseBoard contacts a user when an alert fires. The `type` column is `EMAIL`, `SLACK`, or `WEBHOOK`. The `config` column is JSONB — it holds channel-specific settings. For EMAIL it stores the address, for SLACK it stores the webhook URL, for WEBHOOK it stores the endpoint and optional secret.

---

**File to create:** `src/main/resources/db/migration/V5__create_notification_channels_table.sql`

```sql
CREATE TABLE notification_channels (
    id        UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id   UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type      VARCHAR(50) NOT NULL,
    config    JSONB     NOT NULL,
    is_active BOOLEAN   NOT NULL DEFAULT TRUE,

    CONSTRAINT chk_channel_type CHECK (type IN ('EMAIL', 'SLACK', 'WEBHOOK'))
);

CREATE INDEX idx_notification_channels_user ON notification_channels(user_id);

COMMENT ON COLUMN notification_channels.config IS
  'EMAIL: {"address":"x@y.com"}, SLACK: {"webhookUrl":"..."}, WEBHOOK: {"url":"...","secret":"..."}';
```

---

**Acceptance criteria:**
- [ ] `type` has a CHECK constraint
- [ ] `config` is JSONB — supports flexible channel configurations
- [ ] Migration applies cleanly after V4

---

## Issue #13 — User entity, repository, and UserDetailsService

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #08 (V1 migration — users table exists)
**Required by:** #14 (register uses User), #15 (JWT uses UserDetails), #17 (login), #20 (OAuth2)

---

**Context**

The `User` JPA entity maps exactly to the `users` table from Issue #08. `UserDetailsServiceImpl` bridges Spring Security's authentication system to our database — Spring calls it when it needs to load a user by email.

Never expose the `passwordHash` field in any response object. Use a dedicated response DTO.

---

**Classes to create:**

**`src/main/java/dev/pulseboard/auth/entity/User.java`**
```java
@Entity
@Table(name = "users")
@Data @Builder @NoArgsConstructor @AllArgsConstructor
public class User implements UserDetails {
    @Id @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(unique = true, nullable = false)
    private String email;

    private String passwordHash;
    private String name;
    private String provider;    // LOCAL or GOOGLE
    private String providerId;
    private String role;

    @CreationTimestamp
    private LocalDateTime createdAt;
    @UpdateTimestamp
    private LocalDateTime updatedAt;

    // UserDetails implementation
    @Override public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + role));
    }
    @Override public String getPassword() { return passwordHash; }
    @Override public String getUsername() { return email; }
    @Override public boolean isAccountNonExpired() { return true; }
    @Override public boolean isAccountNonLocked() { return true; }
    @Override public boolean isCredentialsNonExpired() { return true; }
    @Override public boolean isEnabled() { return true; }
}
```

**`src/main/java/dev/pulseboard/auth/repository/UserRepository.java`**
```java
public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByEmail(String email);
    boolean existsByEmail(String email);
    Optional<User> findByProviderAndProviderId(String provider, String providerId);
}
```

**`src/main/java/dev/pulseboard/auth/service/UserDetailsServiceImpl.java`**
```java
@Service @RequiredArgsConstructor
public class UserDetailsServiceImpl implements UserDetailsService {
    private final UserRepository userRepository;

    @Override
    public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
        return userRepository.findByEmail(email)
            .orElseThrow(() -> new UsernameNotFoundException("User not found: " + email));
    }
}
```

**`src/main/java/dev/pulseboard/auth/dto/UserResponse.java`**
```java
public record UserResponse(UUID id, String name, String email, String role, LocalDateTime createdAt) {
    public static UserResponse from(User user) {
        return new UserResponse(user.getId(), user.getName(), user.getEmail(),
                                user.getRole(), user.getCreatedAt());
    }
}
```

---

**Acceptance criteria:**
- [ ] `User` entity compiles and maps to `users` table without JPA errors
- [ ] `UserRepository.findByEmail()` works in a basic integration test
- [ ] `UserResponse` never includes `passwordHash` — confirmed by inspection
- [ ] `UserDetailsServiceImpl` throws `UsernameNotFoundException` for unknown email

---

## Issue #14 — POST /api/auth/register

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #13 (User entity), #06 (SecurityConfig must whitelist this endpoint)
**Required by:** #17 (login requires a registered user), #25 (integration tests)

---

**Context**

This is the first public endpoint. It creates a new user with a hashed password and returns a safe response (no password hash). The endpoint must be accessible without a JWT — the security config from Issue #06 whitelists `/api/auth/**`.

---

**Request DTO:**
```java
public record RegisterRequest(
    @NotBlank String name,
    @Email @NotBlank String email,
    @Size(min = 8, message = "Password must be at least 8 characters") @NotBlank String password
) {}
```

**Controller method:**
```java
@PostMapping("/register")
@Operation(summary = "Register a new user")
@ApiResponse(responseCode = "201", description = "User created")
@ApiResponse(responseCode = "409", description = "Email already registered")
public ResponseEntity<UserResponse> register(@Valid @RequestBody RegisterRequest request) {
    UserResponse response = authService.register(request);
    return ResponseEntity.status(HttpStatus.CREATED).body(response);
}
```

**Service logic:**
1. Check `userRepository.existsByEmail(email)` — throw `DuplicateEmailException` if true (handled by GlobalExceptionHandler Issue #23 → returns 409)
2. Hash password: `passwordEncoder.encode(request.password())`
3. Save user with `provider = "LOCAL"`, `role = "USER"`
4. Return `UserResponse.from(savedUser)`

---

**Acceptance criteria:**
- [ ] `POST /api/auth/register` with valid body returns 201 and `UserResponse` (no passwordHash field)
- [ ] Duplicate email returns 409 with `{"error":"DUPLICATE_EMAIL","message":"...","status":409}`
- [ ] Short password (< 8 chars) returns 400 with field-level validation error
- [ ] Missing email returns 400
- [ ] Endpoint is accessible without JWT

---

## Issue #15 — JwtService

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #06 (JWT config in application.yml)
**Required by:** #16 (JwtAuthFilter uses it to validate), #17 (login uses it to generate tokens), #18 (refresh uses it)

---

**Context**

JwtService is the core of auth-service. It generates and validates all tokens in the system. Access tokens expire in 15 minutes (short — limits damage if leaked). Refresh tokens expire in 7 days and are stored in the DB (Issue #09) so they can be revoked.

The JWT secret must be at least 256 bits (32 bytes / 64 hex chars) for HS256. Reading it from `${JWT_SECRET}` prevents it ever being committed to git.

---

**`src/main/java/dev/pulseboard/auth/security/JwtService.java`**
```java
@Service
public class JwtService {

    @Value("${jwt.secret}")
    private String secret;

    @Value("${jwt.expiry-ms}")
    private long accessExpiryMs;

    @Value("${jwt.refresh-expiry-ms}")
    private long refreshExpiryMs;

    private SecretKey getSigningKey() {
        return Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret));
    }

    public String generateAccessToken(UserDetails user) {
        return Jwts.builder()
            .subject(user.getUsername())
            .claim("type", "access")
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + accessExpiryMs))
            .signWith(getSigningKey())
            .compact();
    }

    public String generateRefreshToken(UserDetails user) {
        return Jwts.builder()
            .subject(user.getUsername())
            .claim("type", "refresh")
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + refreshExpiryMs))
            .signWith(getSigningKey())
            .compact();
    }

    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }

    public boolean isTokenValid(String token, UserDetails userDetails) {
        final String username = extractUsername(token);
        return username.equals(userDetails.getUsername()) && !isTokenExpired(token);
    }

    public boolean isTokenExpired(String token) {
        return extractClaim(token, Claims::getExpiration).before(new Date());
    }

    private <T> T extractClaim(String token, Function<Claims, T> claimsResolver) {
        Claims claims = Jwts.parser()
            .verifyWith(getSigningKey())
            .build()
            .parseSignedClaims(token)
            .getPayload();
        return claimsResolver.apply(claims);
    }
}
```

---

**Acceptance criteria:**
- [ ] `generateAccessToken()` returns a valid JWT that can be decoded at jwt.io
- [ ] `isTokenValid()` returns false for an expired token
- [ ] `isTokenValid()` returns false for a tampered signature
- [ ] JWT secret is read from env — not hardcoded anywhere
- [ ] Unit tests pass (Issue #25 will test this)

---

## Issue #16 — JwtAuthFilter

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #15 (JwtService), #13 (UserDetailsServiceImpl)
**Required by:** #17 (protected endpoints need this running), SecurityConfig (registered here)

---

**Context**

This filter runs before every request and does one job: if there's a valid JWT in the `Authorization` header, it sets the authenticated user in Spring's SecurityContext so downstream code can call `SecurityContextHolder.getContext().getAuthentication()`.

If the token is missing → pass through (SecurityConfig decides if the route requires auth).
If the token is present but invalid → return 401 immediately, do NOT pass to the next filter.

---

**`src/main/java/dev/pulseboard/auth/security/JwtAuthFilter.java`**
```java
@Component @RequiredArgsConstructor
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final UserDetailsServiceImpl userDetailsService;
    private final ObjectMapper objectMapper;

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                    FilterChain chain) throws ServletException, IOException {

        final String authHeader = req.getHeader("Authorization");

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            chain.doFilter(req, res); // No token — let SecurityConfig handle it
            return;
        }

        final String token = authHeader.substring(7);

        try {
            String username = jwtService.extractUsername(token);
            if (username != null && SecurityContextHolder.getContext().getAuthentication() == null) {
                UserDetails userDetails = userDetailsService.loadUserByUsername(username);
                if (jwtService.isTokenValid(token, userDetails)) {
                    UsernamePasswordAuthenticationToken authToken =
                        new UsernamePasswordAuthenticationToken(userDetails, null,
                                                                userDetails.getAuthorities());
                    authToken.setDetails(new WebAuthenticationDetailsSource().buildDetails(req));
                    SecurityContextHolder.getContext().setAuthentication(authToken);
                }
            }
            chain.doFilter(req, res);
        } catch (Exception e) {
            // Token is present but invalid — return 401, stop the chain
            res.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            res.setContentType("application/json");
            res.getWriter().write(objectMapper.writeValueAsString(
                Map.of("error", "INVALID_TOKEN", "message", "JWT is invalid or expired", "status", 401)
            ));
        }
    }
}
```

**Register in SecurityConfig:**
```java
http.addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class);
```

---

**Acceptance criteria:**
- [ ] Request with no `Authorization` header passes through (SecurityConfig handles)
- [ ] Request with valid JWT populates `SecurityContextHolder`
- [ ] Request with tampered JWT returns 401 JSON (not Spring's default error HTML)
- [ ] Request with expired JWT returns 401 JSON

---

## Issue #17 — POST /api/auth/login

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #15 (JwtService generates tokens), #09 (refresh_tokens table to save token), #16 (filter must be registered)
**Required by:** #18 (refresh needs a token to exist), #19 (logout needs a token), #25 (integration tests)

---

**Context**

Login authenticates credentials and returns both token types. The refresh token is saved to the DB. The access token is stateless — not stored anywhere. The response includes `expiresIn` so the frontend knows when to refresh.

---

**Request/Response:**
```java
public record LoginRequest(
    @Email @NotBlank String email,
    @NotBlank String password
) {}

public record AuthResponse(
    String accessToken,
    String refreshToken,
    long expiresIn  // in seconds, e.g. 900
) {}
```

**Service logic:**
```java
public AuthResponse login(LoginRequest request) {
    // 1. Authenticate — throws BadCredentialsException if wrong
    authenticationManager.authenticate(
        new UsernamePasswordAuthenticationToken(request.email(), request.password())
    );

    // 2. Load user and generate tokens
    UserDetails user = userDetailsService.loadUserByUsername(request.email());
    String accessToken = jwtService.generateAccessToken(user);
    String refreshToken = jwtService.generateRefreshToken(user);

    // 3. Save refresh token to DB (delete old ones for this user first)
    refreshTokenRepository.deleteByUserId(foundUser.getId());
    RefreshToken token = RefreshToken.builder()
        .userId(foundUser.getId())
        .token(refreshToken)
        .expiresAt(LocalDateTime.now().plusSeconds(refreshExpiryMs / 1000))
        .build();
    refreshTokenRepository.save(token);

    return new AuthResponse(accessToken, refreshToken, accessExpiryMs / 1000);
}
```

---

**Acceptance criteria:**
- [ ] Valid credentials return 200 with `accessToken`, `refreshToken`, `expiresIn`
- [ ] Wrong password returns 401 with `{"error":"BAD_CREDENTIALS","message":"...","status":401}`
- [ ] Refresh token is saved to `refresh_tokens` table — verifiable with psql
- [ ] Old refresh tokens for the user are deleted before saving the new one

---

## Issue #18 — POST /api/auth/refresh

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #17 (login must work and save a refresh token), #15 (JwtService)
**Required by:** frontend token rotation flow, #25 (integration tests)

---

**Context**

Access tokens expire every 15 minutes. When they do, the frontend sends the refresh token to get a new access token — without making the user log in again. The refresh token must exist in the DB and not be expired. On success, return a new access token (do NOT rotate the refresh token here — keep it simple).

---

**Service logic:**
```java
public AuthResponse refresh(String refreshToken) {
    // 1. Check token exists in DB
    RefreshToken stored = refreshTokenRepository.findByToken(refreshToken)
        .orElseThrow(() -> new InvalidTokenException("Refresh token not found"));

    // 2. Check it hasn't expired in the DB
    if (stored.getExpiresAt().isBefore(LocalDateTime.now())) {
        refreshTokenRepository.delete(stored);
        throw new InvalidTokenException("Refresh token expired");
    }

    // 3. Validate the JWT signature and expiry
    String email = jwtService.extractUsername(refreshToken);
    UserDetails user = userDetailsService.loadUserByUsername(email);

    // 4. Issue new access token
    String newAccessToken = jwtService.generateAccessToken(user);
    return new AuthResponse(newAccessToken, refreshToken, accessExpiryMs / 1000);
}
```

---

**Acceptance criteria:**
- [ ] Valid refresh token returns new access token (200)
- [ ] Non-existent refresh token returns 401
- [ ] Expired refresh token returns 401 and deletes the token from DB

---

## Issue #19 — POST /api/auth/logout

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #17 (a refresh token must exist to delete), #16 (JWT filter must authenticate the user)
**Required by:** #25 (integration tests)

---

**Context**

Logout deletes the user's refresh token from the DB. The access token cannot be revoked (it's stateless) but it expires in 15 minutes anyway. Requiring a valid JWT for logout means the user must be authenticated — you can't log out someone else.

---

**Endpoint:**
```java
@PostMapping("/logout")
@SecurityRequirement(name = "bearerAuth")
public ResponseEntity<Void> logout(Authentication authentication) {
    String email = authentication.getName();
    User user = userRepository.findByEmail(email).orElseThrow();
    refreshTokenRepository.deleteByUserId(user.getId());
    return ResponseEntity.noContent().build(); // 204
}
```

---

**Acceptance criteria:**
- [ ] Valid JWT → 204 and refresh token deleted from DB
- [ ] No JWT → 401 (handled by filter from #16)
- [ ] Calling logout twice with the same token → 204 both times (idempotent)

---

## Issue #20 — OAuth2 Google login

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #13 (User entity), #15 (JwtService), #17 (AuthResponse format)
**Required by:** #25 (integration tests)

---

**Context**

Google OAuth2 login lets users sign in with their Google account. Spring handles the OAuth2 flow automatically — we just need to intercept the success event, find or create a user, and issue our own JWT. We do NOT use Google's session or token after this point.

The `findByProviderAndProviderId` method from Issue #13 finds returning OAuth users. New OAuth users are created with `provider = "GOOGLE"` and no `passwordHash`.

---

**`application.yml` additions:**
```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          google:
            client-id: ${GOOGLE_CLIENT_ID}
            client-secret: ${GOOGLE_CLIENT_SECRET}
            scope: email, profile
```

**`OAuth2SuccessHandler.java`:**
```java
@Component @RequiredArgsConstructor
public class OAuth2SuccessHandler implements AuthenticationSuccessHandler {
    private final UserRepository userRepository;
    private final JwtService jwtService;
    private final RefreshTokenRepository refreshTokenRepository;

    @Override
    public void onAuthenticationSuccess(HttpServletRequest req, HttpServletResponse res,
                                        Authentication auth) throws IOException {
        OAuth2User oauth2User = (OAuth2User) auth.getPrincipal();
        String email = oauth2User.getAttribute("email");
        String name = oauth2User.getAttribute("name");
        String googleId = oauth2User.getAttribute("sub");

        // Find or create user
        User user = userRepository.findByProviderAndProviderId("GOOGLE", googleId)
            .orElseGet(() -> userRepository.save(User.builder()
                .email(email).name(name)
                .provider("GOOGLE").providerId(googleId)
                .role("USER").build()));

        String accessToken = jwtService.generateAccessToken(user);
        String refreshToken = jwtService.generateRefreshToken(user);
        // Save refresh token (same logic as Issue #17)

        // Redirect frontend with tokens
        String redirectUrl = "http://localhost:3000/auth/callback"
            + "?accessToken=" + accessToken
            + "&refreshToken=" + refreshToken;
        res.sendRedirect(redirectUrl);
    }
}
```

---

**Acceptance criteria:**
- [ ] Navigating to `/oauth2/authorization/google` redirects to Google login
- [ ] After Google login, user is created in DB with `provider = 'GOOGLE'`
- [ ] Frontend receives `accessToken` and `refreshToken` as query params
- [ ] Second login with same Google account finds the existing user (no duplicate)

---

## Issue #21 — MonitoredService CRUD

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #10 (V3 migration), #13 (User entity), #16 (JWT filter)
**Required by:** #22 (alert rules belong to services), #46 (health-poller fetches services), #33 (metrics ingest validates ownership)

---

**Context**

These are the endpoints users call to register and manage their backend services in PulseBoard. Ownership is enforced at the application level using `@PreAuthorize` — Spring Security runs the expression before the method executes. Never check ownership manually inside the method body.

The `GET /internal/services/active` endpoint (no JWT, internal only) is consumed by health-poller-service in Issue #46.

---

**Endpoints:**
```
POST   /api/services              → create (201)
GET    /api/services              → list current user's services (200)
GET    /api/services/{id}         → get one (200, 403 if not owner, 404 if not found)
PUT    /api/services/{id}         → update (200, 403 if not owner)
DELETE /api/services/{id}         → delete (204, 403 if not owner)
GET    /internal/services/active  → all active services (no JWT, for health-poller)
```

**`@PreAuthorize` pattern:**
```java
@PreAuthorize("@serviceSecurityService.isOwner(#id, authentication.name)")
```

Create `ServiceSecurityService.java`:
```java
@Service @RequiredArgsConstructor
public class ServiceSecurityService {
    private final MonitoredServiceRepository repo;
    public boolean isOwner(UUID serviceId, String email) {
        return repo.findById(serviceId)
            .map(s -> s.getOwner().getEmail().equals(email))
            .orElse(false);
    }
}
```

---

**Acceptance criteria:**
- [ ] Creating a service returns 201 with service details including generated `id`
- [ ] Listing services only returns services owned by the authenticated user
- [ ] Accessing another user's service returns 403 (not 404 — don't leak existence)
- [ ] Deleting a service returns 204 and cascades to delete its alert rules (from DB constraint in #11)
- [ ] `GET /internal/services/active` returns all active services without requiring JWT

---

## Issue #22 — AlertRule CRUD

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #11 (V4 migration), #21 (service must exist before creating a rule)
**Required by:** #38 (alert-engine evaluates these rules), #39 (alert-engine caches them in Redis)

---

**Context**

Alert rules define the conditions under which an alert fires. The `metric_name` in the rule must match the metric names sent to metrics-ingestion-service (e.g. `cpu_usage`, `memory_usage`, `endpoint_health`). The alert-engine-service fetches active rules per service and caches them in Redis for 60 seconds (Issue #39).

---

**Endpoints:**
```
POST   /api/services/{serviceId}/rules  → create rule (201)
GET    /api/services/{serviceId}/rules  → list rules (200)
PUT    /api/rules/{ruleId}              → update rule (200)
DELETE /api/rules/{ruleId}             → delete rule (204)
GET    /internal/rules/service/{serviceId} → for alert-engine (no JWT)
```

**Valid operators:** `>` `<` `>=` `<=` `==`
**Valid severities:** `INFO` `WARNING` `CRITICAL`

The internal endpoint (`/internal/rules/service/{serviceId}`) is consumed by alert-engine-service in Issue #37 when it evaluates incoming metrics.

---

**Acceptance criteria:**
- [ ] Creating a rule with invalid operator returns 400 with validation error
- [ ] Creating a rule for a service the user doesn't own returns 403
- [ ] `GET /internal/rules/service/{id}` returns only `is_active = true` rules without JWT
- [ ] Deleting a service (Issue #21) also deletes its rules (via DB cascade from #11)

---

## Issue #23 — GlobalExceptionHandler

**Labels:** feature
**Milestone:** M2 — auth-service
**Depends on:** #06 (Spring Boot app running)
**Required by:** every endpoint in M2 (consistent error format), #29 (gateway error format must match)

---

**Context**

Every error response in PulseBoard follows the same JSON format. The `GlobalExceptionHandler` ensures this. Without it, Spring returns its own error format (or HTML) for validation errors, access denied errors, and unhandled exceptions — which would break clients expecting a consistent contract.

This class is the reason Issue #14 can return `409` for duplicate emails and Issue #16 can return `401` in a consistent format.

---

**`src/main/java/dev/pulseboard/auth/exception/GlobalExceptionHandler.java`**
```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        String message = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage())
            .collect(Collectors.joining(", "));
        return ResponseEntity.badRequest()
            .body(new ErrorResponse("VALIDATION_ERROR", message, 400));
    }

    @ExceptionHandler(DuplicateEmailException.class)
    public ResponseEntity<ErrorResponse> handleDuplicateEmail(DuplicateEmailException ex) {
        return ResponseEntity.status(409)
            .body(new ErrorResponse("DUPLICATE_EMAIL", ex.getMessage(), 409));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(AccessDeniedException ex) {
        return ResponseEntity.status(403)
            .body(new ErrorResponse("ACCESS_DENIED", "You do not have permission", 403));
    }

    @ExceptionHandler(EntityNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(EntityNotFoundException ex) {
        return ResponseEntity.status(404)
            .body(new ErrorResponse("NOT_FOUND", ex.getMessage(), 404));
    }

    @ExceptionHandler(InvalidTokenException.class)
    public ResponseEntity<ErrorResponse> handleInvalidToken(InvalidTokenException ex) {
        return ResponseEntity.status(401)
            .body(new ErrorResponse("INVALID_TOKEN", ex.getMessage(), 401));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        log.error("Unhandled exception", ex);
        return ResponseEntity.status(500)
            .body(new ErrorResponse("INTERNAL_ERROR", "An unexpected error occurred", 500));
    }
}

public record ErrorResponse(String error, String message, int status) {}
```

---

**Acceptance criteria:**
- [ ] Validation error → `{"error":"VALIDATION_ERROR","message":"field: reason","status":400}`
- [ ] Duplicate email → `{"error":"DUPLICATE_EMAIL","message":"...","status":409}`
- [ ] Access denied → `{"error":"ACCESS_DENIED","message":"...","status":403}`
- [ ] No endpoint ever returns Spring's default Whitelabel error page
- [ ] No endpoint ever returns a raw Java stack trace

---

## Issue #24 — Swagger/OpenAPI annotations

**Labels:** chore
**Milestone:** M2 — auth-service
**Depends on:** #14 through #22 (all endpoints must exist first)
**Required by:** nothing directly — but required for the agent plan documentation

---

**Context**

Swagger UI is the live documentation for auth-service. Every endpoint must be documented so the gateway (Issue #29) and other services know the exact contract. The JWT bearer button in Swagger lets you test protected endpoints directly in the browser.

---

**Add to main application class:**
```java
@SecurityScheme(
    name = "bearerAuth",
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "JWT"
)
```

**On each controller:** `@Tag(name = "Auth", description = "Authentication endpoints")`

**On each endpoint:**
```java
@Operation(summary = "Register a new user", description = "Creates user account with email/password")
@ApiResponse(responseCode = "201", description = "User created successfully")
@ApiResponse(responseCode = "409", description = "Email already registered")
@ApiResponse(responseCode = "400", description = "Validation error")
```

---

**Acceptance criteria:**
- [ ] All endpoints visible in Swagger UI at `http://localhost:8081/swagger-ui.html`
- [ ] Clicking "Authorize" and entering a JWT allows testing protected endpoints
- [ ] Every endpoint shows correct request/response schemas (not empty)

---

## Issue #25 — Unit and integration tests

**Labels:** test
**Milestone:** M2 — auth-service
**Depends on:** #14, #15, #16, #17, #18, #19, #21, #22, #23 (all features must be built)
**Required by:** #26 (Dockerfile — CI should run tests before building image)

---

**Context**

Tests prove the auth-service is correct and catch regressions when code changes. The integration tests use `@SpringBootTest` with a real H2 in-memory database (configured in Issue #07's `application-test.yml`). The unit tests run without Spring context — fast and isolated.

---

**Required test classes:**

**`JwtServiceTest.java`** (unit test, no Spring context)
```java
// Test: generateAccessToken() → can be decoded, contains correct email
// Test: isTokenValid() → returns false for wrong user
// Test: isTokenValid() → returns false for expired token
// Test: extractUsername() → returns correct email
```

**`AuthIntegrationTest.java`** (`@SpringBootTest @AutoConfigureMockMvc`)
```java
// Test: POST /api/auth/register → 201, user in DB
// Test: POST /api/auth/register duplicate → 409
// Test: POST /api/auth/login valid → 200, tokens returned
// Test: POST /api/auth/login wrong password → 401
// Test: GET /api/services with valid JWT → 200
// Test: GET /api/services with no JWT → 401
// Test: GET /api/services with expired JWT → 401
```

**`MonitoredServiceTest.java`**
```java
// Test: user can create and retrieve their own service
// Test: user cannot access another user's service → 403
// Test: deleting service cascades to delete its alert rules
```

---

**Acceptance criteria:**
- [ ] All tests pass with `./mvnw test`
- [ ] Test coverage for JwtService: 100% of public methods
- [ ] No test uses `@Disabled` or `@Ignore`
- [ ] Tests run in under 30 seconds total

---

## Issue #26 — Dockerize auth-service

**Labels:** infra
**Milestone:** M2 — auth-service
**Depends on:** #25 (tests pass), #06 (application.yml complete)
**Required by:** #28 (gateway routes must reach auth-service container), #05 (full stack docker-compose)

---

**Context**

The Dockerfile uses a two-stage build: the first stage uses the full Maven image to compile and package, the second stage uses only the JRE to run. This keeps the final image small (under 250MB) — no Maven or JDK in production.

The `depends_on` in docker-compose ensures auth-service waits for PostgreSQL and Redis to be healthy before starting (using the health checks defined in Issue #02).

---

**`services/auth-service/Dockerfile`:**
```dockerfile
# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

# Stage 2: Run
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Add to `docker-compose.yml`:**
```yaml
  auth-service:
    build:
      context: ./services/auth-service
    container_name: pulseboard-auth
    ports:
      - "8081:8081"
    env_file:
      - .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8081/actuator/health"]
      interval: 15s
      timeout: 5s
      retries: 5
```

---

**Acceptance criteria:**
- [ ] `docker-compose up auth-service` builds and starts successfully
- [ ] `http://localhost:8081/actuator/health` returns `UP` from inside Docker
- [ ] `http://localhost:8081/swagger-ui.html` is accessible
- [ ] Docker image size is under 250MB: `docker images pulseboard-auth`
- [ ] Service restarts cleanly if PostgreSQL was not yet ready (Flyway retries)

---

---

# MILESTONE 3 — api-gateway

---

## Issue #27 — Bootstrap api-gateway

**Labels:** setup
**Milestone:** M3 — api-gateway
**Depends on:** #26 (auth-service must be running and containerized)
**Required by:** #28, #29, #30 (all gateway features)

---

**Context**

The API gateway is the single entry point for all client traffic. Nothing in PulseBoard should be called directly by a client — everything goes through port 8080. The gateway validates JWTs (so downstream services don't need to), applies rate limits, and routes requests.

Spring Cloud Gateway is reactive (built on WebFlux + Netty) — not the same as Spring MVC. Do not mix WebMVC annotations here.

---

**Dependencies:**
```xml
<dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-gateway</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis-reactive</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
<dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId></dependency>
```

Also add `spring-cloud-dependencies` BOM to `dependencyManagement`.

**`application.yml`:**
```yaml
server:
  port: 8080

spring:
  application:
    name: api-gateway
  data:
    redis:
      host: ${REDIS_HOST}
      port: ${REDIS_PORT}

jwt:
  secret: ${JWT_SECRET}

management:
  endpoints:
    web:
      exposure:
        include: health,prometheus
```

---

**Acceptance criteria:**
- [ ] Gateway starts on port 8080
- [ ] `/actuator/health` returns UP
- [ ] No compilation errors with reactive Spring

---

## Issue #28 — Configure gateway routes

**Labels:** feature
**Milestone:** M3 — api-gateway
**Depends on:** #27 (gateway bootstrapped), #26 (auth-service running)
**Required by:** #29 (JWT filter applies per route), #30 (rate limiter applies per route)

---

**Context**

Routes tell the gateway which URL patterns should be forwarded to which downstream service. The gateway strips the JWT — downstream services trust the `X-User-Id` header injected by the JWT filter (Issue #29) instead of re-validating the token.

---

**`application.yml` routes config:**
```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: auth-service
          uri: http://auth-service:8081
          predicates:
            - Path=/api/auth/**,/api/services/**,/api/rules/**
          filters:
            - name: RequestRateLimiter
              args:
                redis-rate-limiter.replenishRate: 100
                redis-rate-limiter.burstCapacity: 100
                key-resolver: "#{@userKeyResolver}"

        - id: metrics-service
          uri: http://metrics-ingestion-service:8082
          predicates:
            - Path=/api/metrics/**
          filters:
            - name: RequestRateLimiter
              args:
                redis-rate-limiter.replenishRate: 10
                redis-rate-limiter.burstCapacity: 10
                key-resolver: "#{@userKeyResolver}"

        - id: analytics-service
          uri: http://analytics-service:8085
          predicates:
            - Path=/api/analytics/**
```

---

**Acceptance criteria:**
- [ ] `POST http://localhost:8080/api/auth/register` proxies correctly to auth-service
- [ ] Unknown path (`/api/unknown`) returns 404
- [ ] Correct service receives the request (verify in auth-service logs)

---

## Issue #29 — JWT validation GatewayFilter

**Labels:** feature
**Milestone:** M3 — api-gateway
**Depends on:** #15 (JwtService logic — duplicate the validation logic here, do NOT call auth-service for every request), #28 (routes configured)
**Required by:** #30 (rate limiter uses the user identity extracted here), all protected routes

---

**Context**

The gateway validates JWTs itself using the same secret as auth-service. It does NOT call auth-service to validate — that would make auth-service a bottleneck. Both services share `${JWT_SECRET}` from the environment.

On success, the gateway injects `X-User-Id` and `X-User-Email` headers before forwarding — downstream services use these instead of parsing the JWT again.

Whitelisted paths (no JWT required): `/api/auth/register`, `/api/auth/login`, `/api/auth/refresh`, `/actuator/**`

---

**`JwtAuthGatewayFilter.java`:**
```java
@Component
public class JwtAuthGatewayFilter implements GlobalFilter, Ordered {

    private static final List<String> WHITELIST = List.of(
        "/api/auth/register", "/api/auth/login", "/api/auth/refresh"
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();

        if (WHITELIST.stream().anyMatch(path::startsWith)) {
            return chain.filter(exchange);
        }

        String authHeader = exchange.getRequest().getHeaders().getFirst("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return unauthorized(exchange, "Missing authorization header");
        }

        try {
            String token = authHeader.substring(7);
            Claims claims = parseToken(token); // validates signature + expiry
            String userId = claims.get("userId", String.class);
            String email = claims.getSubject();

            ServerHttpRequest mutatedRequest = exchange.getRequest().mutate()
                .header("X-User-Id", userId)
                .header("X-User-Email", email)
                .build();

            return chain.filter(exchange.mutate().request(mutatedRequest).build());

        } catch (JwtException e) {
            return unauthorized(exchange, "Invalid or expired token");
        }
    }

    private Mono<Void> unauthorized(ServerWebExchange exchange, String message) {
        exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
        exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
        String body = """
            {"error":"UNAUTHORIZED","message":"%s","status":401}
            """.formatted(message);
        DataBuffer buffer = exchange.getResponse().bufferFactory()
            .wrap(body.getBytes(StandardCharsets.UTF_8));
        return exchange.getResponse().writeWith(Mono.just(buffer));
    }

    @Override public int getOrder() { return -1; } // run before all other filters
}
```

---

**Acceptance criteria:**
- [ ] `/api/auth/register` is accessible without JWT
- [ ] `/api/services` without JWT returns 401 with JSON (not HTML)
- [ ] `/api/services` with valid JWT returns response from auth-service
- [ ] Downstream services receive `X-User-Id` header (verify in auth-service logs)

---

## Issue #30 — Redis-backed rate limiter

**Labels:** feature
**Milestone:** M3 — api-gateway
**Depends on:** #28 (routes must be configured), #29 (user identity needed for per-user keys)
**Required by:** protects all downstream services from abuse

---

**Context**

Rate limiting is applied per user (not per IP — a user behind a NAT shouldn't be limited by other users). The Redis rate limiter uses a sliding window counter — the key is the user's email from the JWT, set by the filter in Issue #29.

Two tiers: general endpoints get 100 req/min, the metrics ingest endpoint gets 10 req/min (prevents clients from flooding the pipeline).

---

**`KeyResolverConfig.java`:**
```java
@Configuration
public class KeyResolverConfig {
    @Bean
    public KeyResolver userKeyResolver() {
        return exchange -> {
            String userEmail = exchange.getRequest().getHeaders().getFirst("X-User-Email");
            return Mono.just(userEmail != null ? userEmail : "anonymous");
        };
    }
}
```

---

**Acceptance criteria:**
- [ ] Sending 101 requests to `/api/services` in one minute returns 429 on the 101st
- [ ] 429 response includes `Retry-After` header
- [ ] Sending 11 requests to `/api/metrics/ingest` in one minute returns 429
- [ ] Two different users can each send 100 requests without blocking each other

---

## Issue #31 — Dockerize api-gateway

**Labels:** infra
**Milestone:** M3 — api-gateway
**Depends on:** #30 (all gateway features complete), #26 (auth-service in docker-compose)
**Required by:** full stack `docker-compose up` end-to-end test

---

**Dockerfile** (same pattern as #26, port 8080):
```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Add to `docker-compose.yml`:**
```yaml
  api-gateway:
    build:
      context: ./services/api-gateway
    container_name: pulseboard-gateway
    ports:
      - "8080:8080"
    env_file:
      - .env
    depends_on:
      auth-service:
        condition: service_healthy
      redis:
        condition: service_healthy
```

---

**Acceptance criteria:**
- [ ] `docker-compose up` starts gateway after auth-service is healthy
- [ ] `POST http://localhost:8080/api/auth/register` works end-to-end through gateway → auth-service → PostgreSQL
- [ ] Rate limiter works in Docker (Redis reachable from gateway container)

---

---

# MILESTONE 4 — metrics-ingestion-service

---

## Issue #32 — Bootstrap metrics-ingestion-service

**Labels:** setup
**Milestone:** M4 — metrics-ingestion-service
**Depends on:** #31 (gateway running), #02 (Kafka and MongoDB running)
**Required by:** #33, #34, #35

---

**Context**

metrics-ingestion-service is the data entry point. It receives metric data from clients, validates ownership (by calling auth-service), publishes each metric as a Kafka event, and stores the raw data in MongoDB. It does NOT evaluate alert rules — that is alert-engine-service's job.

Port: 8082.

---

**Key `application.yml` additions:**
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
  data:
    mongodb:
      uri: ${MONGO_URI}
      database: pulsedb
```

**`MetricEvent.java`** (shared Kafka message schema):
```java
@Data @Builder @NoArgsConstructor @AllArgsConstructor
public class MetricEvent {
    private String serviceId;
    private String metricName;
    private double value;
    private String unit;
    private Map<String, String> tags;
    private Instant timestamp;
}
```

---

**Acceptance criteria:**
- [ ] Service starts on port 8082
- [ ] `/actuator/health` returns UP
- [ ] Kafka producer connects without errors (check logs)
- [ ] MongoDB connection established (check logs)

---

## Issue #33 — POST /api/metrics/ingest

**Labels:** feature
**Milestone:** M4 — metrics-ingestion-service
**Depends on:** #32 (bootstrapped), #21 (auth-service exposes `/internal/services/active` for ownership check)
**Required by:** #37 (alert-engine consumes from `metrics.raw`), #35 (latest metrics stored in MongoDB)

---

**Context**

This endpoint receives metric data from a client and does three things: validates that the `serviceId` belongs to the authenticated user, publishes each metric to Kafka topic `metrics.raw`, and saves to MongoDB. It returns 202 immediately — the Kafka publish is fire-and-forget.

The user identity comes from the `X-User-Email` header injected by the gateway (Issue #29) — not from a JWT re-validation.

---

**Request:**
```json
{
  "serviceId": "uuid",
  "metrics": [
    { "name": "cpu_usage", "value": 87.5, "unit": "percent", "tags": {"host": "prod-01"} }
  ]
}
```

**Service logic:**
```java
// 1. Validate ownership — call auth-service internal endpoint
boolean isOwner = authServiceClient.isOwner(serviceId, userEmail);
if (!isOwner) throw new AccessDeniedException("Service does not belong to user");

// 2. Publish each metric to Kafka + save to MongoDB
request.metrics().forEach(metric -> {
    MetricEvent event = MetricEvent.builder()
        .serviceId(request.serviceId())
        .metricName(metric.name())
        .value(metric.value())
        .unit(metric.unit())
        .tags(metric.tags())
        .timestamp(Instant.now())
        .build();

    kafkaTemplate.send("metrics.raw", request.serviceId(), event);
    mongoTemplate.insert(event, "metrics_raw");
});
```

---

**Acceptance criteria:**
- [ ] Returns 202 ACCEPTED immediately (does not wait for Kafka acknowledge)
- [ ] Events appear in Kafka topic `metrics.raw` (verify with logs or Kafka UI)
- [ ] Documents saved in MongoDB `metrics_raw` collection
- [ ] `serviceId` belonging to another user returns 403
- [ ] Invalid `serviceId` (not found) returns 404

---

## Issue #34 — POST /api/metrics/ingest/batch

**Labels:** feature
**Milestone:** M4 — metrics-ingestion-service
**Depends on:** #33 (single ingest must work first)
**Required by:** high-volume metric clients sending many metrics at once

---

**Acceptance criteria:**
- [ ] Accepts up to 1000 metrics in one request body
- [ ] Request with > 1000 metrics returns 400 with clear error message
- [ ] All metrics published to Kafka and saved to MongoDB
- [ ] Returns 202

---

## Issue #35 — GET /api/metrics/{serviceId}/latest

**Labels:** feature
**Milestone:** M4 — metrics-ingestion-service
**Depends on:** #33 (metrics must be stored in MongoDB)
**Required by:** dashboard (later) — displays live metric data

---

**Acceptance criteria:**
- [ ] Returns last 20 metrics by default, paginated (`?page=0&size=20`)
- [ ] Max page size is 100 — requests for `size=500` are capped at 100
- [ ] Results sorted by `timestamp` descending (most recent first)
- [ ] Returns 403 if the requesting user does not own the service
- [ ] Returns 404 if serviceId does not exist

---

---

# MILESTONE 5 — alert-engine-service

---

## Issue #36 — Bootstrap alert-engine-service

**Labels:** setup
**Milestone:** M5 — alert-engine-service
**Depends on:** #35 (metrics-ingestion publishes to Kafka — engine needs Kafka running)
**Required by:** #37 through #43

---

**Context**

alert-engine-service has no REST endpoints for external clients. It is purely event-driven — it consumes from Kafka and publishes to Kafka. It reads alert rules from auth-service via REST (then caches in Redis), tracks alert state in Redis, and writes alert history to MongoDB.

Port: 8083 (for actuator only — not exposed through gateway).

---

**Key config:**
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    consumer:
      group-id: alert-engine-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.trusted.packages: "dev.pulseboard.*"
```

**Important:** `auto-offset-reset: earliest` means if the service restarts, it re-reads from the last committed offset — no events are lost.

---

## Issue #37 — Kafka consumer for metrics.raw

**Labels:** feature
**Milestone:** M5 — alert-engine-service
**Depends on:** #36 (bootstrapped), #33 (metrics-ingestion publishes to metrics.raw)
**Required by:** #38 (evaluator called inside this consumer)

---

**Context**

This is the entry point of the alert engine. Every metric event published by metrics-ingestion-service and health-poller-service arrives here. The consumer fetches the alert rules for the service, then calls the evaluator for each rule.

---

**`MetricConsumer.java`:**
```java
@Component @RequiredArgsConstructor @Slf4j
public class MetricConsumer {
    private final AlertRuleEvaluator evaluator;
    private final AlertRuleCache ruleCache;         // Issue #39 — fetches + caches rules
    private final AlertStateManager stateManager;  // Issue #39 — Redis state

    @KafkaListener(topics = {"metrics.raw", "health.checks"}, groupId = "alert-engine-group")
    public void onMetric(MetricEvent event) {
        log.debug("Received metric: {} for service {}", event.getMetricName(), event.getServiceId());

        List<AlertRule> rules = ruleCache.getRulesForService(event.getServiceId());

        rules.stream()
            .filter(rule -> rule.getMetricName().equals(event.getMetricName()))
            .filter(AlertRule::isActive)
            .forEach(rule -> evaluator.evaluate(event, rule));
    }
}
```

---

**Acceptance criteria:**
- [ ] Consumer group ID is `alert-engine-group` (not shared with other consumers)
- [ ] Service logs metric receipt at DEBUG level
- [ ] Consumer handles deserialization errors gracefully — logs and skips, does not crash
- [ ] Consuming from both `metrics.raw` AND `health.checks` topics

---

## Issue #38 — Alert rule evaluator

**Labels:** feature
**Milestone:** M5 — alert-engine-service
**Depends on:** #37 (consumer calls this), #22 (rules come from auth-service)
**Required by:** #39 (evaluator calls state manager after evaluation), #43 (unit tests)

---

**Context**

The evaluator is a pure function — it takes a metric event and a rule, compares them, and tells the state manager what to do. No database calls, no Kafka calls — just math. This makes it trivially testable.

---

**`AlertRuleEvaluator.java`:**
```java
@Component @RequiredArgsConstructor
public class AlertRuleEvaluator {
    private final AlertStateManager stateManager;

    public void evaluate(MetricEvent event, AlertRule rule) {
        boolean breached = switch (rule.getOperator()) {
            case ">"  -> event.getValue() > rule.getThreshold();
            case "<"  -> event.getValue() < rule.getThreshold();
            case ">=" -> event.getValue() >= rule.getThreshold();
            case "<=" -> event.getValue() <= rule.getThreshold();
            case "==" -> event.getValue() == rule.getThreshold();
            default   -> throw new IllegalArgumentException("Unknown operator: " + rule.getOperator());
        };

        stateManager.transition(event, rule, breached);
    }
}
```

---

**Acceptance criteria:**
- [ ] All 5 operators work correctly for boundary values (e.g. `>= 80` with value `80` → breached)
- [ ] Unknown operator throws `IllegalArgumentException` (not NullPointerException)
- [ ] Unit tests in Issue #43 cover all 5 operators plus boundary cases

---

## Issue #39 — Redis alert state machine + rule cache

**Labels:** feature
**Milestone:** M5 — alert-engine-service
**Depends on:** #38 (evaluator calls state manager), #41 (state manager publishes Kafka events)
**Required by:** #40 (deduplication relies on state), #43 (unit tests)

---

**Context**

State is stored in Redis as a simple string per rule: `alert:state:{ruleId}` = `"OK"` or `"FIRING"`. Redis survives service restarts. The rule cache stores rules in Redis for 60 seconds to avoid calling auth-service on every single metric event.

---

**`AlertStateManager.java`:**
```java
@Component @RequiredArgsConstructor
public class AlertStateManager {
    private final RedisTemplate<String, String> redis;
    private final AlertEventPublisher publisher; // Issue #41

    public void transition(MetricEvent event, AlertRule rule, boolean breached) {
        String stateKey = "alert:state:" + rule.getId();
        String currentState = redis.opsForValue().get(stateKey);

        if (breached && !"FIRING".equals(currentState)) {
            redis.opsForValue().set(stateKey, "FIRING");
            publisher.publishFired(event, rule);  // → alerts.fired topic
        } else if (!breached && "FIRING".equals(currentState)) {
            redis.opsForValue().set(stateKey, "OK");
            publisher.publishResolved(event, rule); // → alerts.resolved topic
        }
        // FIRING + still breached → do nothing (deduplication)
        // OK + not breached → do nothing
    }
}
```

**`AlertRuleCache.java`:**
```java
@Component @RequiredArgsConstructor
public class AlertRuleCache {
    private final RedisTemplate<String, List<AlertRule>> redis;
    private final AuthServiceClient authClient; // REST client to auth-service

    public List<AlertRule> getRulesForService(String serviceId) {
        String cacheKey = "rules:" + serviceId;
        List<AlertRule> cached = redis.opsForValue().get(cacheKey);
        if (cached != null) return cached;

        List<AlertRule> rules = authClient.getActiveRules(serviceId);
        redis.opsForValue().set(cacheKey, rules, Duration.ofSeconds(60));
        return rules;
    }
}
```

---

**Acceptance criteria:**
- [ ] Redis key `alert:state:{ruleId}` is set after a metric breaches a rule
- [ ] Second breach of the same rule does NOT publish to Kafka (deduplication)
- [ ] Recovery publishes to `alerts.resolved` and sets state to `OK`
- [ ] Cache key `rules:{serviceId}` has 60-second TTL in Redis

---

## Issue #40 — Alert deduplication test

**Labels:** test
**Milestone:** M5 — alert-engine-service
**Depends on:** #39 (state machine)
**Required by:** #43 (combined in unit tests — separate issue to track explicitly)

---

**Context**

Deduplication is the most critical behaviour of the alert engine. Without it, every 30-second polling cycle sends a new alert email while a service is down. This issue verifies deduplication works end-to-end.

---

**Manual verification steps:**
1. Send a metric that breaches a rule → verify event appears in `alerts.fired` topic
2. Send the same metric again (still breached) → verify NO new event in `alerts.fired`
3. Send a metric below the threshold → verify event appears in `alerts.resolved`
4. Send the breaching metric again → verify NEW event in `alerts.fired` (fresh alert)

Check Redis state at each step: `docker exec pulseboard-redis redis-cli get "alert:state:{ruleId}"`

---

**Acceptance criteria:**
- [ ] Step 1: one event in `alerts.fired`
- [ ] Step 2: no new event in `alerts.fired`
- [ ] Step 3: one event in `alerts.resolved`, Redis state = `OK`
- [ ] Step 4: one new event in `alerts.fired`, Redis state = `FIRING`

---

## Issue #41 — Publish AlertEvent to Kafka

**Labels:** feature
**Milestone:** M5 — alert-engine-service
**Depends on:** #39 (state manager calls this publisher), #37 (consumer triggers the chain)
**Required by:** notification-service (later milestone) consumes from these topics, #42 (MongoDB save)

---

**`AlertEvent.java`:**
```java
@Data @Builder @NoArgsConstructor @AllArgsConstructor
public class AlertEvent {
    private String alertId;       // random UUID, generated here
    private String ruleId;
    private String serviceId;
    private String serviceName;
    private String metricName;
    private double metricValue;
    private double threshold;
    private String operator;
    private String severity;      // INFO, WARNING, CRITICAL
    private String message;       // human-readable e.g. "cpu_usage is 87.5 — threshold 80.0"
    private Instant triggeredAt;
}
```

**`AlertEventPublisher.java`:**
```java
@Component @RequiredArgsConstructor
public class AlertEventPublisher {
    private final KafkaTemplate<String, AlertEvent> kafkaTemplate;
    private final AlertHistoryRepository historyRepo; // Issue #42

    public void publishFired(MetricEvent metric, AlertRule rule) {
        AlertEvent event = buildEvent(metric, rule);
        kafkaTemplate.send("alerts.fired", metric.getServiceId(), event);
        historyRepo.save(AlertHistory.from(event)); // Issue #42
    }

    public void publishResolved(MetricEvent metric, AlertRule rule) {
        AlertEvent event = buildEvent(metric, rule);
        kafkaTemplate.send("alerts.resolved", metric.getServiceId(), event);
        historyRepo.updateResolved(rule.getId(), Instant.now()); // Issue #42
    }
}
```

---

**Acceptance criteria:**
- [ ] `alerts.fired` events are visible in Kafka (check via logs or Kafka UI)
- [ ] `alerts.resolved` events are visible in Kafka
- [ ] `alertId` is unique per event (UUID generated fresh each time)
- [ ] `message` field is human-readable and includes the actual metric value and threshold

---

## Issue #42 — Save alert history to MongoDB

**Labels:** feature
**Milestone:** M5 — alert-engine-service
**Depends on:** #41 (AlertEventPublisher calls this), #36 (MongoDB connected)
**Required by:** analytics-service reads alert history, dashboard shows alert history

---

**`AlertHistory.java` (MongoDB document):**
```java
@Document(collection = "alert_history")
@Data @Builder @NoArgsConstructor @AllArgsConstructor
public class AlertHistory {
    @Id private String id;
    private String ruleId;
    private String serviceId;
    private String severity;
    private Instant triggeredAt;
    private Instant resolvedAt;   // null until resolved
    private double metricValue;
    private String message;
}
```

**On `alerts.resolved` — update `resolvedAt`:**
```java
public void updateResolved(String ruleId, Instant resolvedAt) {
    mongoTemplate.updateFirst(
        Query.query(Criteria.where("ruleId").is(ruleId).and("resolvedAt").isNull()),
        Update.update("resolvedAt", resolvedAt),
        AlertHistory.class
    );
}
```

---

**Acceptance criteria:**
- [ ] MongoDB `alert_history` collection has a document for each fired alert
- [ ] `resolvedAt` is set when the alert resolves (not null)
- [ ] `resolvedAt` stays null for ongoing alerts

---

## Issue #43 — Unit tests for alert-engine-service

**Labels:** test
**Milestone:** M5 — alert-engine-service
**Depends on:** #38, #39, #40, #41 (all features built)
**Required by:** CI pipeline — tests must pass before merging

---

**`AlertRuleEvaluatorTest.java`:**
```java
// @Test void greaterThan_belowThreshold_notBreached()
// @Test void greaterThan_atThreshold_notBreached()       ← boundary: > not >=
// @Test void greaterThan_aboveThreshold_breached()
// @Test void greaterThanOrEqual_atThreshold_breached()   ← boundary: >= includes equal
// @Test void lessThan_aboveThreshold_notBreached()
// @Test void equals_exactMatch_breached()
// @Test void unknownOperator_throwsException()
```

**`AlertStateMachineTest.java`:**
```java
// @Test void okThenBreach_publishesFiredEvent()
// @Test void firingThenBreach_doesNotPublishAgain()       ← deduplication
// @Test void firingThenRecover_publishesResolvedEvent()
// @Test void okThenRecover_doesNothing()
// @Test void firingThenRecoverThenBreach_publishesFiredAgain()
```

---

**Acceptance criteria:**
- [ ] All tests pass with `./mvnw test`
- [ ] Tests do not use the real Redis or Kafka — use Mockito mocks
- [ ] `AlertRuleEvaluatorTest` covers all 5 operators with both sides of the boundary

---

---

# MILESTONE 6 — health-poller-service

---

## Issue #44 — Bootstrap health-poller-service

**Labels:** setup
**Milestone:** M6 — health-poller-service
**Depends on:** #43 (alert-engine running to consume health events), #02 (Kafka running)
**Required by:** #45 through #48

---

**Context**

health-poller-service's job is to be the heartbeat of PulseBoard. Every 30 seconds it asks auth-service for the list of active services, pings every one of them in parallel, and publishes the results as `endpoint_health` metric events. The alert-engine then evaluates these events against any rules with `metric_name = "endpoint_health"`.

This is why a user can set an alert rule like "if `endpoint_health < 1.0` → fire CRITICAL alert" and PulseBoard will detect downtime.

Port: 8086.

---

**Key `application.yml`:**
```yaml
server:
  port: 8086

spring:
  application:
    name: health-poller-service
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}

poller:
  interval-ms: 30000
  timeout-seconds: 5
  thread-pool-size: 20

management:
  endpoints:
    web:
      exposure:
        include: health,prometheus
```

**Main class:**
```java
@SpringBootApplication
@EnableScheduling
public class HealthPollerApplication { ... }
```

> `@EnableScheduling` is mandatory — without it, `@Scheduled` annotations are silently ignored.

---

**Acceptance criteria:**
- [ ] Service starts on port 8086
- [ ] `/actuator/health` returns UP
- [ ] `@EnableScheduling` is on the main class

---

## Issue #45 — @Scheduled polling job

**Labels:** feature
**Milestone:** M6 — health-poller-service
**Depends on:** #44 (bootstrapped)
**Required by:** #46 (job calls fetch), #47 (job calls ping), #48 (job calls publish)

---

**Context**

The `@Scheduled` method is the orchestrator. It calls the fetch, ping, and publish steps in sequence. It must not block the scheduler thread — if one cycle takes longer than 30 seconds, the next cycle must not be skipped.

Use `@Scheduled(fixedDelay = 30000)` (not `fixedRate`) — `fixedDelay` starts the 30-second countdown AFTER the previous cycle finishes, preventing overlapping cycles.

---

**`HealthPollerJob.java`:**
```java
@Component @RequiredArgsConstructor @Slf4j
public class HealthPollerJob {
    private final ServiceFetcher fetcher;    // Issue #46
    private final EndpointPinger pinger;     // Issue #47
    private final HealthEventPublisher pub;  // Issue #48

    @Scheduled(fixedDelayString = "${poller.interval-ms}")
    public void runCycle() {
        log.info("Health polling cycle started");
        try {
            List<MonitoredServiceDTO> services = fetcher.fetchActiveServices();
            log.info("Polling {} services", services.size());

            List<PingResult> results = pinger.pingAll(services);

            results.forEach(pub::publish);
            log.info("Cycle complete — {} results published", results.size());
        } catch (Exception e) {
            log.error("Polling cycle failed", e);
            // Do NOT re-throw — a failed cycle should not stop the scheduler
        }
    }
}
```

---

**Acceptance criteria:**
- [ ] Job runs automatically every 30 seconds (verify in logs)
- [ ] A failed cycle (auth-service down) logs an error but does NOT stop future cycles
- [ ] `fixedDelay` is used, not `fixedRate`

---

## Issue #46 — Fetch active services from auth-service

**Labels:** feature
**Milestone:** M6 — health-poller-service
**Depends on:** #45 (job calls this), #21 (auth-service exposes `/internal/services/active`)
**Required by:** #47 (pinger needs the service list)

---

**Context**

`WebClient` (non-blocking) is mandatory here. `RestTemplate` (blocking) would hold one thread per request and severely limit the poller's ability to handle many services concurrently.

The internal endpoint at auth-service requires no JWT — it is internal-only, not exposed through the gateway.

---

**`ServiceFetcher.java`:**
```java
@Component @RequiredArgsConstructor
public class ServiceFetcher {
    private final WebClient webClient;

    @Value("${auth.service.url:http://auth-service:8081}")
    private String authServiceUrl;

    public List<MonitoredServiceDTO> fetchActiveServices() {
        return webClient.get()
            .uri(authServiceUrl + "/internal/services/active")
            .retrieve()
            .bodyToFlux(MonitoredServiceDTO.class)
            .collectList()
            .timeout(Duration.ofSeconds(10))
            .onErrorReturn(List.of()) // if auth-service is down, return empty list
            .block();
    }
}
```

**`MonitoredServiceDTO.java`:**
```java
public record MonitoredServiceDTO(String id, String name, String endpointUrl) {}
```

**Add `WebClient` bean:**
```java
@Bean
public WebClient webClient() {
    return WebClient.builder().build();
}
```

---

**Acceptance criteria:**
- [ ] Returns list of active services from auth-service
- [ ] If auth-service is unreachable → returns empty list and logs WARNING (does not crash)
- [ ] Uses WebClient — confirmed by no import of `RestTemplate`

---

## Issue #47 — Ping endpoints in parallel

**Labels:** feature
**Milestone:** M6 — health-poller-service
**Depends on:** #46 (needs the service list to ping)
**Required by:** #48 (ping results are published)

---

**Context**

All services are pinged in parallel using a fixed thread pool. The pool size (20) limits concurrency — 200 services would need 10 rounds of 20. A 5-second timeout per ping means the worst-case cycle time is `ceiling(services/20) * 5s`. For 200 services that's 50 seconds — acceptable with `fixedDelay`.

A 2xx HTTP status = UP. Anything else (4xx, 5xx, timeout, connection refused) = DOWN.

---

**`EndpointPinger.java`:**
```java
@Component
public class EndpointPinger {
    private final ExecutorService pool = Executors.newFixedThreadPool(20);
    private final WebClient webClient = WebClient.builder().build();

    public List<PingResult> pingAll(List<MonitoredServiceDTO> services) {
        List<Future<PingResult>> futures = services.stream()
            .map(s -> pool.submit(() -> ping(s)))
            .toList();

        return futures.stream().map(f -> {
            try { return f.get(10, TimeUnit.SECONDS); }
            catch (Exception e) {
                return new PingResult(null, false, -1, 0);
            }
        }).toList();
    }

    private PingResult ping(MonitoredServiceDTO service) {
        try {
            long start = System.currentTimeMillis();
            Integer status = webClient.get()
                .uri(service.endpointUrl())
                .retrieve()
                .toBodilessEntity()
                .timeout(Duration.ofSeconds(5))
                .map(r -> r.getStatusCode().value())
                .onErrorReturn(0)
                .block();
            long responseMs = System.currentTimeMillis() - start;
            boolean isUp = status != null && status >= 200 && status < 300;
            return new PingResult(service.id(), isUp, responseMs, status != null ? status : 0);
        } catch (Exception e) {
            return new PingResult(service.id(), false, -1, 0);
        }
    }
}

public record PingResult(String serviceId, boolean isUp, long responseMs, int statusCode) {}
```

---

**Acceptance criteria:**
- [ ] 20 services are pinged simultaneously (not sequentially)
- [ ] A service that times out after 5s returns `isUp = false`
- [ ] A service returning 200 returns `isUp = true`
- [ ] A service returning 500 returns `isUp = false`
- [ ] A service with an invalid URL (connection refused) returns `isUp = false`

---

## Issue #48 — Publish health check results to Kafka

**Labels:** feature
**Milestone:** M6 — health-poller-service
**Depends on:** #47 (ping results), #37 (alert-engine consumes from health.checks)
**Required by:** alert-engine evaluates these events — this closes the full monitoring loop

---

**Context**

This is the final step that closes the entire PulseBoard loop:

```
User registers service (#21)
  → health-poller pings it (#47)
  → publishes metric event (#48) to health.checks
  → alert-engine consumes it (#37)
  → evaluator checks rules (#38)
  → state machine transitions (#39)
  → alert event published to alerts.fired (#41)
  → notification-service sends alert (later milestone)
```

The metric value is `1.0` (up) or `0.0` (down) — a numeric value so the alert engine's rule evaluator (which works on numbers) can evaluate it with `< 1.0`.

---

**`HealthEventPublisher.java`:**
```java
@Component @RequiredArgsConstructor
public class HealthEventPublisher {
    private final KafkaTemplate<String, MetricEvent> kafkaTemplate;

    public void publish(PingResult result) {
        if (result.serviceId() == null) return; // skip failed fetches

        MetricEvent event = MetricEvent.builder()
            .serviceId(result.serviceId())
            .metricName("endpoint_health")
            .value(result.isUp() ? 1.0 : 0.0)
            .unit("status")
            .tags(Map.of(
                "status_code", String.valueOf(result.statusCode()),
                "response_ms", String.valueOf(result.responseMs())
            ))
            .timestamp(Instant.now())
            .build();

        kafkaTemplate.send("health.checks", result.serviceId(), event);
    }
}
```

---

**Acceptance criteria:**
- [ ] One Kafka event per service per polling cycle in `health.checks` topic
- [ ] Events visible in Kafka (logs or Kafka UI)
- [ ] Alert engine receives and processes the events (verify in alert-engine logs)
- [ ] Setting an alert rule `endpoint_health < 1.0` on a stopped service fires an alert
- [ ] Full loop verified: stopped service → poller detects → alert fires → saved to MongoDB
