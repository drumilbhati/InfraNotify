# PulseBoard — Services

This folder contains all backend microservices that make up PulseBoard.
Each service is independently deployable, has its own `Dockerfile`, and communicates
with other services via Kafka (async) or REST (sync).

---

---

## Service Overview

| Service | Port | Responsibility |
|---|---|---|
| api-gateway | 8080 | Routes all traffic, rate limiting, JWT validation |
| auth-service | 8081 | Users, services, alert rules, JWT, OAuth2 |
| metrics-ingestion-service | 8082 | Ingest metric data, publish to Kafka |
| alert-engine-service | 8083 | Evaluate rules, track alert state, fire alerts |
| notification-service | 8084 | Email, WebSocket push, Slack webhook delivery |
| health-poller-service | 8086 | Scheduled endpoint pinging, uptime tracking |
| analytics-service | 8085 | Aggregated metrics, uptime %, alert history |

---

## Decision Log

Every technology choice below was made deliberately. This section explains the *why*
behind each decision — not just the *what*.

---

### Language — Java 21

**Chosen over:** Go, Python (FastAPI), Node.js

Java 21 is the primary language across all services for two reasons.
First, the team has existing Java experience — switching languages mid-project burns
time on syntax rather than building. Second, Java 21 introduces virtual threads
(Project Loom), which eliminates the old concurrency limitations that made people
reach for Go or Node.js. The JVM's JIT compiler makes modern Java performance
competitive with Go in real-world I/O-bound workloads.

Mixing languages was considered and rejected. Running two runtimes (Java + Node.js)
doubles the Dockerfile complexity, splits the debugging context, and adds cognitive
overhead with no meaningful benefit at this scale.

---

### Framework — Spring Boot 3.x

**Chosen over:** Quarkus, Micronaut, plain Java

Spring Boot provides production-grade dependency injection, security, database
integration, and health monitoring out of the box. The auto-configuration model means
services can be bootstrapped quickly without writing boilerplate wiring code.

Spring Boot 3.x specifically was chosen (not 2.x) because it targets Java 17+ baseline,
has native support for virtual threads via Project Loom, and integrates directly with
OpenTelemetry for distributed tracing without third-party bridges.

The broader Spring ecosystem (Spring Cloud Gateway, Spring Security, Spring Data,
Spring Kafka) means every layer of the stack speaks the same configuration language,
which keeps the learning curve consistent across services.

---

### Notification-service — Node.js (Express)

**Chosen over:** Java Spring Boot

The notification service is the one exception to the Java-first rule across this
project, and it is a deliberate exception.

The notification service does exactly three things: consume an event from Kafka,
push it to a connected browser over WebSocket, and fire an email or webhook. Every
single one of these is an I/O operation — waiting on a network response, writing to
a socket, calling an external mail server. There is no CPU-intensive computation,
no complex business logic, and no relational data to manage.

Node.js is architected around this exact workload. Its event loop handles thousands
of concurrent I/O operations on a single thread without blocking — because while one
email is in flight, the loop is free to push a WebSocket frame to another client.
A Java Spring Boot service handles this with a thread-per-request model, meaning
each in-flight operation holds a thread. For a service that is almost entirely
waiting on external systems, this is an inefficient use of resources.

The practical result is that Node.js handles high concurrency with significantly
lower memory overhead than an equivalent Spring Boot service doing the same I/O-bound
work. When 500 users are simultaneously connected over WebSocket and alerts are firing
across all of them, this difference is felt.

The secondary reason is ecosystem fit. The two core libraries used —
`socket.io` for WebSocket management and `kafkajs` for Kafka consumption — are
first-class Node.js libraries with large communities, extensive documentation, and
active maintenance. The WebSocket story in particular is more ergonomic in Node.js
than in Spring Boot's STOMP model for a service that only needs outbound push.

The tradeoff accepted here is running two runtimes in the same project. This adds
a second Dockerfile pattern, a separate `package.json` dependency tree, and a
context switch for anyone working across services. This cost was judged acceptable
because the notification service is small, isolated, and has a single well-defined
boundary — it only consumes from Kafka and pushes outward. It does not call other
services and nothing calls it directly.

---

### API Gateway — Spring Cloud Gateway

**Chosen over:** Kong, NGINX, AWS API Gateway, custom Spring Boot service

Spring Cloud Gateway runs as a reactive Spring Boot application, which means it shares
the same deployment model, configuration format, and observability stack as every other
service in this project. There is no separate process to manage, no additional runtime
to learn, and no plugin system to navigate.

Kong and NGINX are excellent production choices but introduce operational complexity
(separate installation, their own config DSL, separate health monitoring) that is
unnecessary for a project of this scope.

AWS API Gateway was rejected because it ties the project to a specific cloud provider
and removes the ability to run the full stack locally with `docker-compose up`.

Spring Cloud Gateway gives us route-level rate limiting (via Redis), JWT validation
as a gateway filter, and request/response logging — all configured in a single
`application.yml`.

---

### Message Queue — Apache Kafka

**Chosen over:** RabbitMQ, Redis Pub/Sub, AWS SQS

Kafka is optimized for high-throughput, ordered, and replayable event streams.
Metric data is inherently append-only and time-ordered — exactly the workload Kafka
is designed for.

The key advantage over RabbitMQ is **replayability**. If the alert engine crashes
and restarts, it can resume consuming from where it left off. With RabbitMQ, messages
that were not acknowledged are lost or require complex dead-letter queue configuration.

Redis Pub/Sub was rejected for this role because it has no persistence — if a consumer
is offline when a message is published, the message is gone. This is acceptable for
ephemeral notifications but not for metric events that must be processed exactly once.

Kafka topics in this project:

| Topic | Producer | Consumer |
|---|---|---|
| `metrics.raw` | metrics-ingestion-service | alert-engine-service, analytics-service |
| `alerts.fired` | alert-engine-service | notification-service |
| `alerts.resolved` | alert-engine-service | notification-service |
| `notifications.sent` | notification-service | analytics-service |
| `health.checks` | health-poller-service | metrics-ingestion-service |

---

### Cache & Rate Limiter — Redis 7

**Chosen over:** Memcached, in-memory (Caffeine), Hazelcast

Redis is used for three distinct jobs in this project, and it is the best tool for
each of them.

For **caching**, Redis provides TTL-based expiry natively. Frequently read data
(user records, service configs, alert rules) is cached with short TTLs to reduce
database load without stale-data risk.

For **rate limiting**, Spring Cloud Gateway's built-in `RequestRateLimiter` filter
uses Redis to implement a sliding-window counter. This works correctly even when
the gateway is scaled to multiple instances — a counter stored in-process (Caffeine)
would be per-instance only and would not enforce the global limit correctly.

For **alert state tracking**, the alert engine stores each rule's current state
(`FIRING` or `OK`) in Redis with the key `alert:state:{ruleId}`. This prevents
the engine from re-firing an alert that is already active (deduplication) and
survives service restarts since state is stored externally.

Memcached was rejected because it does not support pub/sub or expiry callbacks.
Caffeine was rejected for rate limiting because it cannot share state across instances.

---

### Relational Database — PostgreSQL 16

**Chosen over:** MySQL, H2, SQLite

PostgreSQL is used by auth-service to store users, monitored services, alert rules,
and notification channel configurations. These entities have strict foreign key
relationships and benefit from transactional guarantees — a user deletion should
cascade to their services and rules atomically.

PostgreSQL was chosen over MySQL for its superior support for JSONB columns
(used in `notification_channels.config`), UUID primary keys via `gen_random_uuid()`,
and more expressive constraint syntax.

H2 and SQLite were rejected outright. Both are fine for unit tests but are not
viable for production deployments. Using them would require switching databases
between environments, which introduces environment-specific bugs.

Flyway is used for all schema migrations. `spring.jpa.hibernate.ddl-auto` is set
to `validate` in production — never `create` or `update`. This ensures the schema
is always version-controlled and reproducible.

---

### Document Database — MongoDB 7

**Chosen over:** PostgreSQL JSONB, Cassandra, DynamoDB

MongoDB stores two types of data: raw metric events (written by metrics-ingestion-service)
and alert history logs (written by alert-engine-service).

Both of these are schema-flexible. A metric payload from a Node.js service looks
different from one sent by a Java Spring Boot service — they may have different tag
structures, units, and field names. Forcing this into a rigid relational schema would
require either a very wide nullable table or a complicated EAV design. A document
store handles this naturally.

MongoDB was also chosen for its write throughput. Metric events can arrive in
thousands per second during peak load. MongoDB's write model is optimized for this
pattern in a way that PostgreSQL, optimized for transactional consistency, is not.

Cassandra was considered and rejected — it is operationally complex and better suited
for data volumes far beyond this project's scope.

---

### Auth — Spring Security + JWT + OAuth2

**Chosen over:** Keycloak, Auth0, Firebase Auth, session-based auth

JWT-based stateless authentication was chosen because it fits the microservices model
naturally. Each service can validate a JWT independently using the shared secret —
no round-trip to a central auth server is required on every request.

Access tokens are short-lived (15 minutes). Refresh tokens are stored in PostgreSQL
and rotated on each use. This limits the blast radius of a leaked token without
requiring server-side session storage.

Google OAuth2 is supported via Spring Security's OAuth2 client. On successful
OAuth2 login, PulseBoard issues its own JWT — the system does not rely on Google's
session or token format beyond the initial identity verification.

Keycloak and Auth0 were rejected because they introduce external runtime dependencies.
Running the full PulseBoard stack locally should require only `docker-compose up` —
not a separately managed identity server.

---

### Real-time Delivery — WebSockets (STOMP)

**Chosen over:** Server-Sent Events (SSE), long polling, REST polling

WebSockets provide a persistent bidirectional connection between the server and the
browser. When an alert fires, the notification service pushes it to the connected
dashboard client in under a second, with no polling overhead.

STOMP (Simple Text Oriented Messaging Protocol) is used over raw WebSockets because
Spring's WebSocket support natively integrates with STOMP, providing topic-based
subscriptions (`/topic/alerts/{userId}`) that map cleanly to the alert-per-user model.

SSE (Server-Sent Events) was considered — it is simpler and sufficient for one-way
push. It was rejected because WebSockets also support future bidirectional use cases
(e.g., real-time rule editing) without requiring a protocol change.

---

### Observability — Prometheus + Grafana + OpenTelemetry + Jaeger

**Chosen over:** Datadog, New Relic, CloudWatch

The open-source observability stack was chosen to keep the project fully self-hosted
and cloud-agnostic. Every service exposes a `/actuator/prometheus` endpoint that
Prometheus scrapes on a 15-second interval. Grafana connects to Prometheus as a
data source and renders dashboards.

OpenTelemetry auto-instruments all HTTP calls, Kafka producer/consumer operations,
and database queries with trace IDs. Jaeger collects and visualizes these traces,
making it possible to follow a single metric ingest request across all six services
it touches.

Datadog and New Relic are excellent but require API keys and send data to external
servers. For a locally runnable project, self-hosted tooling is the correct choice.

---

### CI/CD — GitHub Actions

**Chosen over:** Jenkins, CircleCI, GitLab CI

GitHub Actions runs natively on the same platform where the source code lives.
There is no separate CI server to provision or maintain. Workflow files live in the
repository alongside the code, so the build process is version-controlled and
reviewable like any other change.

The pipeline runs on every push: build all services, run unit tests, build Docker
images, and push to Docker Hub. A failing test blocks the merge — enforcing the
principle that the main branch is always deployable.

Jenkins was rejected for its operational overhead. CircleCI and GitLab CI were
rejected simply because the project already lives on GitHub.

---

### Containers & Orchestration — Docker + Kubernetes

**Chosen over:** bare-metal deployment, Docker Swarm, Nomad

Docker ensures every service runs identically in development, CI, and production.
The `docker-compose.yml` at the project root starts the entire stack — all seven
services plus Kafka, Redis, PostgreSQL, MongoDB, Prometheus, Grafana, and Jaeger —
with a single command.

Kubernetes is used for production deployment, specifically for Horizontal Pod
Autoscaling (HPA) on `metrics-ingestion-service`. This is the service that receives
the most traffic (every metric from every monitored service flows through it) and
benefits from automatic scaling under load.

Docker Swarm was rejected because Kubernetes has become the industry standard for
container orchestration and is the expected tool in most backend engineering roles.
