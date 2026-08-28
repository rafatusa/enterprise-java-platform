# Enterprise Java Platform

A Spring Boot task-management API on AWS EC2, delivered through a fully gated
GitHub Actions pipeline. Every release must clear coverage, mutation, static
analysis, security and performance budgets before it reaches production — and
rolls itself back if the deployed version fails its health checks.

---

## Stack

| Layer | Choice |
|-------|--------|
| Runtime | Java 17 (Temurin), Spring Boot 3.3 |
| Database | PostgreSQL 16, on-host, bound to `127.0.0.1` |
| Web | Nginx reverse proxy (the only public entry point) |
| Infrastructure | AWS EC2 `t3.medium`, Ubuntu 22.04, Elastic IP, IAM role, CloudWatch Logs |
| IaC | Terraform (S3 remote state) |
| Bootstrap | Puppet (masterless `puppet apply`) |
| Deployment | Ansible (roles: postgresql, application, nginx) |
| Registry | GitHub Container Registry (GHCR) |

## Quality gates

The pipeline **fails automatically** when any of these is breached. Each is
enforced by the tool's own configuration in `pom.xml`, not by parsing logs — so
`mvn verify` fails locally exactly as CI does.

| Gate | Threshold | Enforced by |
|------|-----------|-------------|
| Line coverage | ≥ 90% | JaCoCo `<limit>` → `jacoco:check` |
| Branch coverage | ≥ 85% | JaCoCo `<limit>` → `jacoco:check` |
| Mutation score | ≥ 70% | PIT `<mutationThreshold>` |
| Critical security issues | 0 | OWASP DC `failBuildOnCVSS=7`, Trivy, Semgrep |
| High vulnerabilities | 0 | Trivy `--severity CRITICAL,HIGH --exit-code 1` |
| Secrets detected | 0 | Gitleaks `--exit-code 1` |
| Checkstyle violations | 0 | `failOnViolation=true`, `violationSeverity=warning` |
| PMD violations | none at priority ≤ 3 | `failurePriority=3` |
| SpotBugs High priority | 0 | `threshold=High`, `failOnError=true` |
| p95 latency @ 200 VUs | < 400 ms | k6 threshold |
| Error rate | < 1% | k6 threshold |

> **These numbers are the contract.** If a gate fails, fix the code — never lower
> the threshold. The thresholds live in `pom.xml` properties so that changing one
> is a visible, reviewable diff rather than a quiet edit inside a CI step.

## Pipeline

17 stages. Everything before `package` runs in parallel where dependencies allow.

```
build ─┬─ format ───────────────┐
       ├─ static-analysis ──────┤
       ├─ test ─┬─ mutation ────┤
       │        └─ sonarqube ───┤
       ├─ contract-tests ───────┼─ package ─ tf-check ─ provision ─ configure ─ verify ─ perf ─ release
       └─ dependency-scan ──────┤
          secret-scan ──────────┤
          sast ─────────────────┘
```

| Stage | What it does |
|-------|--------------|
| `build` | Maven compile |
| `format` | Spotless (google-java-format) |
| `static-analysis` | Checkstyle, PMD, CPD, SpotBugs |
| `test` | JUnit 5, Mockito, Spring Boot IT, REST Assured, JaCoCo |
| `contract-tests` | Pact provider verification |
| `mutation` | PIT mutation testing |
| `sonarqube` | SonarQube analysis + quality gate |
| `secret-scan` | Gitleaks |
| `sast` | Semgrep (java, security-audit, OWASP Top 10) |
| `dependency-scan` | OWASP Dependency Check, CycloneDX SBOM, Trivy filesystem |
| `package` | Jar, Docker build, Trivy container scan, GHCR push |
| `tf-check` | `terraform fmt`, `validate`, `plan` |
| `provision` | `terraform apply` |
| `configure` | Puppet bootstrap, then Ansible deployment |
| `verify` | Health + smoke tests, **auto-rollback on failure** |
| `perf` | k6 load test (200 VUs / 15 min) |
| `release` | GitHub Release with every report attached |

### The report-then-gate pattern

The pipeline spec does not support `if:` on steps. A scanner that fails would
therefore skip its own artifact upload and hide the evidence. So each scanner
script **always exits 0** and writes its report and exit code to `reports/`;
the artifact uploads; then a separate `*-gate.sh` step reads the recorded exit
code and fails the build.

Do not "simplify" this back into a single `mvn` invocation — you would lose the
report on exactly the runs where you need it.

### Rollback

Rollback is owned by `scripts/ci/verify-with-rollback.sh`, not by a CI
conditional. It runs the full validation suite and, on failure, invokes
`ansible/rollback.yml` to restore the previous release, then exits non-zero.

Releases are laid out for this:

```
/opt/app/releases/<sha>/app.jar
/opt/app/current   -> the live release
/opt/app/previous  -> the rollback target
```

Rollback is a symlink swap plus a restart — no rebuild, and it works by hand
without CI:

```bash
ansible-playbook -i "<host>," -u ubuntu --private-key <key> ansible/rollback.yml
```

## API

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/api/v1/auth/login` | public |
| `GET` | `/api/v1/tasks` | Bearer |
| `GET` | `/api/v1/tasks/urgent` | Bearer |
| `GET` | `/api/v1/tasks/{id}` | Bearer |
| `POST` | `/api/v1/tasks` | Bearer |
| `PUT` | `/api/v1/tasks/{id}` | Bearer |
| `PATCH` | `/api/v1/tasks/{id}/status?value=` | Bearer |
| `DELETE` | `/api/v1/tasks/{id}` | Bearer |
| `GET` | `/actuator/health`, `/actuator/info` | public |
| `GET` | `/swagger-ui/index.html`, `/v3/api-docs` | public |

```bash
TOKEN=$(curl -s -X POST http://<host>/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"operator","password":"<password>"}' | jq -r .token)

curl http://<host>/api/v1/tasks -H "Authorization: Bearer $TOKEN"
```

## Running locally

```bash
# Unit tests only
mvn test

# Everything, including integration tests and the coverage gate
mvn verify

# Mutation testing
mvn test-compile org.pitest:pitest-maven:mutationCoverage

# Fix formatting the gate would reject
mvn spotless:apply
```

Tests run against in-memory H2 in PostgreSQL compatibility mode, so no database
is needed locally. The real PostgreSQL schema is exercised on the deployed host
by the smoke tests.

## Required secrets

Set automatically by the platform: `PROJECT_NAME`, `TF_STATE_BUCKET`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SSH_USER`, `SSH_PRIVATE_KEY`,
`SSH_PUBLIC_KEY`, `GITHUB_TOKEN`.

Set for this project:

| Secret | Purpose | Required |
|--------|---------|----------|
| `DB_PASSWORD` | PostgreSQL application role | yes |
| `JWT_SECRET` | HS256 token signing key | yes |
| `APP_AUTH_PASSWORD` | Operator password used by smoke + k6 | yes |
| `APP_AUTH_PASSWORD_HASH` | bcrypt hash of the above, deployed to the host | yes |
| `SONAR_TOKEN`, `SONAR_HOST_URL` | SonarQube analysis | optional — stage skips with a warning |
| `PACT_BROKER_URL`, `PACT_BROKER_TOKEN` | Publish contract results | optional — verifies locally without |
| `NVD_API_KEY` | Speeds up OWASP Dependency Check | optional — slow without |

**Optional means the stage degrades visibly, not silently.** SonarQube and Pact
both require servers this project does not provision; making them hard failures
would block every deploy on infrastructure you may not have.

### Hosted integrations are NOT configured in this deployment

`SONAR_TOKEN` / `SONAR_HOST_URL` and `PACT_BROKER_URL` / `PACT_BROKER_TOKEN`
are **deliberately unset**. Concretely:

| | Without the secrets | What still enforces quality |
|---|---|---|
| **SonarQube** | `scripts/ci/sonar.sh` emits `::warning`, writes a skip marker to `reports/`, exits 0. No dashboard, no quality gate call. | Coverage (JaCoCo 90/85), mutation (PIT 70), Checkstyle, PMD, SpotBugs, Semgrep — all hard-fail `mvn verify`. Sonar was the aggregation layer, not the gate. |
| **Pact broker** | Verification results are not published; no `can-i-deploy` check. | Contracts in `src/test/resources/pacts` are verified **locally on every run** by `TaskProviderPactTest`; a broken contract fails the build. |

Adding the secrets later turns both on with **no code change** — the scripts
detect them at runtime. Nothing needs rewriting if you adopt SonarCloud or a
broker.

## Security notes

- The application binds `127.0.0.1:8080`. Nginx on `:80` is the only public path.
- PostgreSQL listens on `localhost` only and is never exposed to the network.
- The systemd unit runs as the unprivileged `appuser` with `NoNewPrivileges`,
  `PrivateTmp`, `ProtectSystem=full` and `ProtectHome`.
- The instance IAM role grants only `logs:PutLogEvents` scoped to this project's
  log groups; no credentials are stored on the host.
- SSH accepts key auth only — no passwords, no root login (Puppet `hardening`).
- `.env` on the host is mode `0640`, owned by `appuser`, written with `no_log`.
- Test signing keys are **generated at runtime** (`TestKeys`), never committed,
  so no key-shaped literal exists in the repository for a scanner to miss.
- There is **no default credential anywhere**: `application.properties` and
  `app.env.j2` ship no fallback password or signing key, and `site.yml` asserts
  the secrets are present, so a missing secret fails the deploy loudly.

## Documentation

| Document | Contents |
|----------|----------|
| [docs/architecture.md](docs/architecture.md) | Architecture, sequence and deployment diagrams |
| [docs/operations.md](docs/operations.md) | Deploying, rollback, secret rotation, scaling |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Symptom-first diagnosis |
| [docs/openapi.yaml](docs/openapi.yaml) | API specification |

## Known limitations

- **Single instance.** No HA; an instance replacement is a brief outage.
- **On-host PostgreSQL.** No automated backups or point-in-time recovery.
  Moving to RDS is the first upgrade if the data matters.
- **HTTP only.** TLS needs a domain name; add certbot or an ALB with ACM.
- **`t3.medium` is burstable.** Sustained load beyond the benchmark will exhaust
  CPU credits. Use `m7i.large` for genuinely steady traffic.
- **No SonarQube dashboard and no Pact broker** — see above. Local enforcement
  is complete; only the hosted aggregation/publishing layers are absent.

---

Built and deployed with **UDAP**.
