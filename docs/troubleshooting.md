# Troubleshooting

Organised by **symptom**, because that is what you have when something breaks.
Each entry: how to confirm the cause, then how to fix it.

General rule: read the **first** error in a log, not the last. Later errors are
usually consequences.

---

## Pipeline failures

### `test` — coverage gate failed

```
Rule violated for bundle enterprise-java-platform: lines covered ratio is 0.87, but expected minimum is 0.90
```

Real. Some code you added is untested. Open `reports/tests/jacoco/index.html`
from the `jacoco-and-test-reports` artifact — it shows exactly which lines and
branches are uncovered.

**Fix:** write the missing tests. **Do not** lower `jacoco.line.coverage` in
`pom.xml`, and do not add classes to the JaCoCo `<excludes>` to dodge the number.
The existing exclusions (`Application`, `config`, `dto`, `entity`) cover types
with no behaviour to test; a service or controller does not belong there.

### `mutation` — mutation score below 70%

```
Mutation score of 62 is below threshold of 70
```

Your tests execute the code but do not *assert* on its behaviour — mutating a
condition or return value did not make any test fail. Open
`reports/pit/index.html` and look for `SURVIVED` mutants.

**Fix:** strengthen assertions. A test that calls a method and asserts only "no
exception" kills nothing. Assert the returned value, the persisted state, and the
branch actually taken.

> If PIT reports **"could not determine the score"** rather than a low number,
> that is a *tool error*, not a test-quality problem — usually
> `pitest-maven` / `pitest-junit5-plugin` being too old for the JUnit Platform
> the Spring Boot parent manages. Upgrade the two as a **pair**. Do not touch
> `pit.mutation.threshold`.

### `static-analysis` — Checkstyle/PMD/SpotBugs

The gate script prints which tool failed; the reports are in the
`static-analysis-reports` artifact.

- **Checkstyle** — any violation fails (`violationSeverity=warning`). Most are
  formatting: run `mvn spotless:apply` first, which fixes many of them.
- **PMD** — only priority ≤ 3 fails. A priority 1–2 finding (resource leak,
  broken equals/hashCode) is almost always a real defect.
- **SpotBugs** — `threshold=High`. High-priority SpotBugs findings are rarely
  false positives; read the description before assuming otherwise.

If a finding genuinely does not apply, add a **narrowly scoped** exclusion to
`config/spotbugs/exclude.xml` or `config/pmd/ruleset.xml` **with a comment
explaining why**. Never widen the exclusion to a whole package to clear a queue.

### `format` — Spotless

```
The following files had format violations: src/main/java/...
```

**Fix:** `mvn spotless:apply && git commit`. That is the whole procedure.

### `secret-scan` — Gitleaks found a secret

**Treat the credential as compromised immediately** — it is, the moment it is
committed, regardless of whether the repository is private.

1. **Rotate the credential first.** Before cleaning history.
2. Remove it from the working tree; use a secret reference instead.
3. If it was pushed, scrub history (`git filter-repo`) or accept it as burned.

Only if it is genuinely **not** a secret (a hash, a test fixture, a placeholder),
prefer **restructuring the code so it is no longer credential-shaped** — assemble
the value at runtime from parts — over allowlisting. Allowlisting a path blinds
the scanner to a real leak in that same file. This project has no path
allowlists for that reason.

### `sast` — Semgrep

This gate fails in **two distinct ways** and the error message says which. Do not
start hunting for a vulnerability before checking which one you have.

#### "Semgrep reported ERROR-severity findings"

Real findings. The gate step prints each one — rule ID, `file:line`, message and
the offending source line — so you do not need to open the artifact to triage.
Java ERROR-severity rules usually flag injection, deserialization or crypto
misuse: real classes of bug.

**Fix** the code. If it is a false positive, add `// nosemgrep: <rule-id>` on the
specific line with a justification comment. Never disable the rule globally.

#### "the Semgrep scanner could not run"

```
::error::SAST gate FAILED — the Semgrep scanner could not run.
Reason: pip install semgrep failed (see the install log above).
```

**No vulnerability was reported — the scan never executed.** The build still
fails, deliberately: unscanned code is unverified code, not approved code. But
the fix is in the runner, not in your source.

Semgrep needs network access twice: to PyPI (to install) and to `semgrep.dev`
(to fetch the `p/java`, `p/security-audit`, `p/owasp-top-ten` and `p/secrets`
rule packs). Check, in order:

1. **Is this the UDAP rehearsal sandbox rather than CI?** The sandbox has no
   outbound PyPI access, so `pip install semgrep` always fails there. This is
   expected and is **not** a defect in the project — GitHub-hosted runners have
   full network access and the stage runs normally. Do not "fix" it by removing
   the stage or by making the gate tolerant.
2. A PyPI or semgrep.dev outage — re-run the job.
3. A corporate proxy/egress rule on a self-hosted runner — allowlist
   `pypi.org`, `files.pythonhosted.org` and `semgrep.dev`.
4. An unsupported Python version on the runner.

The scan writes `reports/security/semgrep/semgrep.status` (`ok` or `tool-error`)
next to the report so this distinction survives into the artifact.

### `dependency-scan` — OWASP or Trivy

```
One or more dependencies were identified with vulnerabilities that have a CVSS score greater than or equal to '7.0'
```

The **gate step** prints everything you need: for Trivy, each CRITICAL/HIGH with
the package, installed version and **fixed version**; for OWASP, each CVSS ≥ 7
finding with its CVE id, the jar, and the **matched CPE range**. Read the range
before doing anything — it tells you immediately whether the shipped version is
genuinely inside it.

> Findings are printed by the **gate** step, not the scan step. The scan step
> always exits 0 (report-then-gate), so `gh run view --log-failed` only ever
> shows the gate. Anything a human needs in order to diagnose belongs there.
>
> **Trivy prints before OWASP on purpose.** Log retrieval truncates the tail of
> long output, and the short Trivy block sat invisible behind a long OWASP list
> for four consecutive runs. Put the scarcest information first.

**Fix:** upgrade the dependency. Spring Boot's parent POM manages most versions,
so bumping `spring-boot-starter-parent` often clears several at once.

**Before pinning any version, confirm it exists in the registry the build
actually resolves from** — `repo1.maven.org`, *not* the project's GitHub tags. A
git tag is cut before the artifacts are staged and released to Maven Central.
This project has been bitten by that twice. The cheapest reliable check is a
build.

**After any version bump, re-read the scan.** A bump can move you *into* range
for advisories that were not previously reported. Raising Tomcat 10.1.55 →
10.1.57 fixed four CVEs and surfaced three new ones. Never assume a suppression
set is stable across an upgrade.

If no fixed release exists yet, add a **time-boxed, documented** entry to
`config/owasp/suppressions.xml`. **Scope the `packageUrl` to every artifact the
CVE is reported against** — the gate prints that list at the end of the OWASP
group for exactly this reason. Tomcat's embed distribution ships as *both*
`tomcat-embed-core` and `tomcat-embed-websocket`, and the same CVE is reported
against both; a suppression scoped to one leaves the other red.

**A CPE match at the *product* level does not mean the vulnerable *module* is
present.** `log4j-api` is a facade jar of interfaces; the layout flaws reported
against it (`XmlLayout`, `Rfc5424Layout`, `JsonTemplateLayout`) all live in
`log4j-core`, which this project does not ship. Likewise `angus-activation` is
the MIME activation framework, not Jakarta Mail. Verify which classes are
actually on the classpath before deciding — and write down what you checked.

Do not lower `failBuildOnCVSS`; that silently disables the gate for every
dependency, forever.

Two failure modes are distinguished, as with Semgrep: a Trivy status of
`tool-error` means the scanner could not run (usually a bad version pin producing
a 404 on the release asset), **not** that findings exist.

Note: `dependency-scan` can fail for code you did not touch. The NVD publishes
new CVEs continuously. This is the gate working.

> **`NVD_API_KEY` matters.** Without it the NVD feed is anonymously rate-limited
> and the scan takes ~23 minutes with incomplete range data; with it, ~4 minutes
> and complete data. The Maven plugin reads the **Maven property**
> `nvd.api.key` — the `NVD_API_KEY` *environment variable* alone is the
> standalone CLI's convention and is silently ignored by the plugin. It is
> passed as `-Dnvd.api.key` in `scripts/ci/dependency-scan.sh`.

#### Worked example — when to upgrade instead of suppress

`CVE-2026-65898` (CVSS 7.2) reported DOMPurify < 3.4.11 inside the `swagger-ui`
bundle shipped by springdoc 2.8.6. It is **not** in the suppressions file,
because Swagger UI is served to real browsers at `/swagger-ui.html` — the
vulnerable code is genuinely reachable. It was fixed by raising
`springdoc.version` to **2.8.17**. Reachable component + published fix = upgrade,
every time.

#### OPEN SECURITY ITEM — accepted risk, review by 2026-11-27

`config/owasp/suppressions.xml` currently carries **nine suppressions that are
not dismissals** (category B). They are accepted risk with no available fix:

| CVE | CVSS | Issue | Fixed in |
|-----|------|-------|----------|
| CVE-2026-65905 | 9.8 | Tomcat DIGEST authentication bypass | 10.1.58 |
| CVE-2026-65637 | 9.8 | Improper input validation | 10.1.58 |
| CVE-2026-68525 | 9.1 | Tomcat FORM authorization bypass | 10.1.58 |
| CVE-2026-65182 | 9.1 | Security constraint bypass (longer path) | 10.1.58 |
| CVE-2026-68569 | 8.1 | Improper authentication | 10.1.58 |
| CVE-2026-66422 | 8.1 | `security-role-ref` used as Realm role alias | 10.1.58 |
| CVE-2026-65183 | 8.1 | TOCTOU race creating unix domain sockets | 10.1.58 |
| CVE-2026-68763 | 7.5 | HTTP/2 allocation leak on stream reset | 10.1.58 |
| CVE-2026-65927 | 7.5 | Rewrite valve `[N]` flag off-by-one | 10.1.58 |

All nine genuinely apply to the embedded Tomcat this service runs on, and all
are reported against **both** `tomcat-embed-core-10.1.57.jar` and
`tomcat-embed-websocket-10.1.57.jar`. They are suppressed **only** because
`10.1.58` is tagged in the Apache git repository but **has not been published to
Maven Central**, so there is nothing to upgrade to.

`tomcat.version` is pinned to `10.1.57`, the highest published version, which
*does* remediate CVE-2026-59084, CVE-2026-59083, CVE-2026-55276 and
CVE-2026-53434 — those are **fixed, not suppressed**, and no entry for them
exists.

**Compensating controls** (these reduce, not eliminate, exposure):

- The application uses **no Tomcat DIGEST or FORM authentication** and declares
  **no `<security-constraint>`** and **no `<security-role-ref>`**. All
  authentication and authorization is the Spring Security JWT filter chain
  (`JwtAuthenticationFilter`), which is never reached through a Tomcat Realm.
  That covers the five Realm/constraint CVEs.
- CVE-2026-65183 needs a **unix domain socket connector** and a local
  unprivileged user. The connector is TCP on `127.0.0.1:8080`, no unix socket is
  configured, and the box has no interactive users beyond the deploy account.
- CVE-2026-68763 needs **HTTP/2**. The connector is HTTP/1.1 only — no
  `Http2Protocol` upgrade protocol is configured, and nginx proxies over
  HTTP/1.1 — so no HTTP/2 stream can be opened against Tomcat.
- CVE-2026-65927 needs the **Tomcat rewrite valve**. No `rewrite.config` exists
  and no `RewriteValve` is declared; rewriting happens in nginx.
- Tomcat is not internet-facing: nginx terminates and proxies, and the security
  group exposes only 80/443.

**Action:** check
<https://repo1.maven.org/maven2/org/apache/tomcat/embed/tomcat-embed-core/>
for `10.1.58` or later. The moment it is published, raise `<tomcat.version>` in
`pom.xml` and **delete all nine entries**. Do not re-date them without
re-checking Central.

### `package` — container scan failed

The image is **not pushed** when this fails, which is deliberate: a vulnerable
image in a registry outlives the pipeline run.

Usually the base image is stale. `eclipse-temurin:17-jre-jammy` is rebuilt
regularly — re-running the pipeline often picks up a patched base, and the
runtime stage runs `apt-get upgrade` to clear fixable OS-package CVEs at build
time. If a finding is in a package with no fix available, `--ignore-unfixed` is
already set, so what you are seeing has a fix.

### `tf-check` — `terraform fmt -check` failed

**Fix:** `cd infra && terraform fmt -recursive && git commit`.

### `provision` — Terraform apply

**"Resource already exists"** — the backend init flags drifted. Every `init` in
this pipeline must use identical `-backend-config` flags including
`-reconfigure`. Fix the flags; **never** write import scripts to work around lost
state.

**Quota or permission errors** (`UnauthorizedOperation`, `VcpuLimitExceeded`) are
account-level. No amount of retrying helps — request a quota increase or fix the
IAM policy.

**"InvalidKeyPair.Duplicate"** — a previous run left a key pair Terraform no
longer tracks. Confirm it belongs to this project (`Project` tag), then remove it
and re-run.

### `configure` — Ansible

**`UNREACHABLE`** — this is a network/SSH problem, not a playbook problem. Check
in order: security group allows 22; the instance is `running`; the SSH key file
is mode `600`; `SSH_USER` matches the AMI (`ubuntu` for Ubuntu, `ec2-user` for
Amazon Linux/RHEL).

> A denial listing `publickey,gssapi-keyex,gssapi-with-mic` means the host is
> **Amazon Linux/RHEL family** and you are using the wrong login user. Ubuntu
> offers plain `publickey`. That signature distinguishes a user/AMI mismatch from
> a bad key — check it before touching key material.

**`couldn't resolve module/action`** — a module outside `ansible.builtin` that
was not installed. The configure stage installs `community.general` and
`community.postgresql`. Ansible resolves every module before the first task runs,
so this fails instantly.

**`404 Not Found` on apt** — a stale package index, not a missing package. The
playbook uses plain `update_cache: true` with retries precisely to avoid this;
never add `cache_valid_time` on a freshly provisioned host.

**`remote_tmp ... mode 0700` warning** — benign. The real failure is below it.

### `verify` — smoke tests failed, rollback triggered

The `deployment-summary` artifact names which of the seven checks failed. Match
it in the table below:

| Failed check | Look at |
|--------------|---------|
| `/actuator/health` | App did not start — `journalctl -u app -n 100` |
| PostgreSQL connectivity | Wrong `DB_PASSWORD`, or postgres not running |
| Nginx reverse proxy | `nginx -t`, vhost enabled, default site removed |
| Swagger UI / OpenAPI | Springdoc misconfigured or security blocking the path |
| JWT protection returns ≠401 | SecurityConfig `permitAll` list too broad |
| Login issued no token | `APP_AUTH_PASSWORD` and the derived hash disagree |
| Task API smoke test | Database schema — check Flyway history |

### `perf` — benchmark failed

```
Performance gate FAILED — p95 latency exceeded 400 ms and/or the error rate exceeded 1%.
```

Open `k6-summary.html`. Then distinguish:

- **Latency climbs steadily through the run** → CPU credit exhaustion on the
  burstable instance. Move to `m7i.large`.
- **Latency is flat but high** → application or query problem. Check the
  PostgreSQL slow-query log (statements > 1s are logged).
- **Errors cluster at ramp-up** → connection pool too small
  (`hikari.maximum-pool-size`), or nginx `worker_connections`.
- **`setup() failed: login returned 401`** → `APP_AUTH_PASSWORD` does not match
  the deployed hash. The benchmark never ran.

### `release` — GitHub Release failed

Usually a tag collision when two deploys run on the same date and short SHA, or
`contents: write` permission missing on the token.

---

## Runtime problems

### The host is down

Work outward from the app:

```bash
curl -sv http://<ip>/actuator/health          # 1. from outside
ssh ubuntu@<ip>                               # 2. can you reach it at all
sudo systemctl status app nginx postgresql    # 3. what is running
sudo journalctl -u app -n 200 --no-pager      # 4. why did it stop
df -h                                         # 5. disk full is a common cause
```

| Symptom | Likely cause |
|---------|--------------|
| Connection refused on 80 | nginx stopped |
| 502 Bad Gateway | nginx up, app down — check `journalctl -u app` |
| 503 with `db: DOWN` | PostgreSQL stopped or credentials wrong |
| SSH times out | Security group, or the instance is stopped/terminated |
| Everything sluggish | Disk full or CPU credits exhausted |

### 502 Bad Gateway

Nginx is running; the app is not answering on `127.0.0.1:8080`.

```bash
sudo systemctl status app
sudo journalctl -u app -n 100 --no-pager
sudo ss -tlnp | grep 8080
curl -s http://127.0.0.1:8080/actuator/health
```

Common causes: the JVM failed at startup (a bad `.env` value, a Flyway checksum
mismatch), out of memory (check `dmesg | grep -i kill`), or the app is still
booting — it takes 30–60s and the unit restarts every 10s on failure.

### The app restarts in a loop

```bash
sudo journalctl -u app -n 200 --no-pager | head -60
```

Read the **first** stack trace. Recurring causes:

- `FlywayValidateException` — a migration was edited after being applied.
- `Cannot create PoolableConnectionFactory` — wrong `DB_PASSWORD` in
  `/opt/app/shared/app.env`, or postgres is down.
- `WeakKeyException` — `JWT_SECRET` is shorter than 32 bytes; HS256 requires it.
- `Port 8080 already in use` — an orphaned process from a previous release:
  `sudo systemctl stop app; sudo pkill -f app.jar; sudo systemctl start app`.

### Every request returns 401

Either the token is genuinely invalid, or `JWT_SECRET` changed. Rotating
`JWT_SECRET` invalidates all previously issued tokens — clients must log in
again. If nothing was rotated, verify the `Authorization: Bearer <token>` header
is actually being sent; a missing header is indistinguishable from a bad one at
the HTTP layer.

### Disk full

```bash
sudo du -sh /opt/app/releases/* /home/ubuntu/.m2 /var/log/*
```

The Maven repository (`~/.m2`) and old releases are the usual culprits.
`keep_releases: 3` prunes releases each deploy; `~/.m2` is never pruned and is
safe to delete — the next deploy re-downloads.

---

## Escalate when

- Terraform reports quota, billing or IAM errors — account-level, needs a human
  with console access.
- The SSH key pair is inconsistent (derived public key ≠ `SSH_PUBLIC_KEY`) —
  rotate project keys from Integrations; do not experiment with key formats.
- Rollback ran and the host is *still* unhealthy — both the new and previous
  release are failing, which usually means the database or the host itself, not
  the code.
- The same failure recurs after three distinct fix attempts — stop and reassess
  the diagnosis rather than trying a fourth variation of the same idea.
