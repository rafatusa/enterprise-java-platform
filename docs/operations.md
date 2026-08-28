# Operations Guide

Procedures for running this system. Every command here is meant to be executable
at 03:00 by someone who did not build it.

---

## 1. At a glance

| | |
|---|---|
| Public URL | `http://<elastic-ip>/` |
| Health | `http://<elastic-ip>/actuator/health` |
| API docs | `http://<elastic-ip>/swagger-ui/index.html` |
| SSH | `ssh -i <key> ubuntu@<elastic-ip>` |
| Logs (host) | `/opt/app/logs/application.log`, `journalctl -u app` |
| Logs (AWS) | CloudWatch `/enterprise-java-platform/{application,nginx,postgresql}` |
| Service | `app.service` (also `nginx`, `postgresql`) |
| Releases | `/opt/app/releases/<sha>/`, `current` and `previous` symlinks |

Find the IP:

```bash
cd infra && terraform output -raw public_ip
```

---

## 2. Deploying

Deployment is `workflow_dispatch` on the `deploy` workflow, or the platform's
Deploy action. There is **no push-to-deploy** — releases are deliberate.

A deploy runs all 17 stages. Expect **25–40 minutes**, dominated by:
- OWASP Dependency Check (5–15 min; much slower without `NVD_API_KEY`)
- PIT mutation testing (~5 min)
- The k6 benchmark (18 min: 2 ramp + 15 steady + 1 down)
- Maven's first build on a fresh host (~3 min)

### Deploying a change

1. Merge to `main`.
2. Dispatch the deploy workflow.
3. Watch `verify` — that is the gate that decides whether the release stands.
4. Check the `deployment-summary` artifact for the per-check table.

### What happens if verification fails

Automatic. `verify-with-rollback.sh` restores the previous release, re-checks
health, and fails the stage. You will find in the logs either:

- `Rolled back successfully — the PREVIOUS release is live and healthy.`
  The site is up on the old version. Fix forward at your own pace.
- `Rollback completed but host still unhealthy` or `Rollback playbook FAILED`.
  **Page someone.** Go to [troubleshooting](troubleshooting.md#the-host-is-down).

---

## 3. Rollback

### Automatic

Built into the `verify` stage. Nothing to do.

### Manual

When you need the previous version back outside a deploy:

```bash
ansible-playbook -i "<elastic-ip>," -u ubuntu \
  --private-key ~/.ssh/deploy_key \
  ansible/rollback.yml
```

This repoints `current` at `previous`, restarts, and verifies health. It refuses
with a clear message if there is no previous release (first deploy).

### Rolling back further

Only the last two releases are symlinked, but `keep_releases: 3` retains three
on disk:

```bash
ssh ubuntu@<ip> 'ls -1dt /opt/app/releases/*/'
ssh ubuntu@<ip> 'sudo ln -sfn /opt/app/releases/<sha>/ /opt/app/current'
ssh ubuntu@<ip> 'sudo systemctl restart app'
curl --fail http://<ip>/actuator/health
```

To go back beyond what is on disk, use the platform's **Rollback to stable**
action, which reverts the repository to the last green deploy and redeploys.

> **Database migrations are not rolled back.** Flyway rolls forward only. If a
> release included a destructive migration, a code rollback will run the old code
> against the new schema. Write migrations to be backward-compatible for one
> release: add columns, do not rename or drop until the next.

---

## 4. Secrets

| Secret | Rotate when | After rotating |
|--------|-------------|----------------|
| `DB_PASSWORD` | Suspected exposure, staff change | Redeploy (Ansible resets the role password) |
| `JWT_SECRET` | Suspected exposure | Redeploy — **all issued tokens become invalid** |
| `APP_AUTH_PASSWORD` + `APP_AUTH_PASSWORD_HASH` | Staff change | Must be rotated **together** |
| `SONAR_TOKEN`, `PACT_BROKER_TOKEN`, `NVD_API_KEY` | Provider policy | Next run picks them up |

Generate a password and its hash together — they must match or login breaks:

```bash
PW=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
echo "APP_AUTH_PASSWORD=$PW"
htpasswd -bnBC 10 "" "$PW" | tr -d ':\n' | sed 's/\$2y/\$2a/'   # the hash
```

Set both as repository secrets, then redeploy.

> Passwords must be **alphanumeric only**. `%`, `$`, quotes and URL-special
> characters break connection strings, shell interpolation and property files.

---

## 5. Monitoring

### Health

```bash
curl -s http://<ip>/actuator/health | jq
```

`status: UP` plus a `db` component `UP` means the app is running *and* can reach
PostgreSQL. A `503` with `db: DOWN` is a database problem, not an app problem.

### Logs

```bash
# Application, live
ssh ubuntu@<ip> 'sudo journalctl -u app -f'

# Application file log (what CloudWatch ships)
ssh ubuntu@<ip> 'sudo tail -f /opt/app/logs/application.log'

# Nginx
ssh ubuntu@<ip> 'sudo tail -f /var/log/nginx/access.log'
ssh ubuntu@<ip> 'sudo tail -f /var/log/nginx/error.log'

# PostgreSQL (slow queries >1s are logged)
ssh ubuntu@<ip> 'sudo tail -f /var/log/postgresql/postgresql-*-main.log'
```

In CloudWatch, log groups are `/enterprise-java-platform/{application,nginx,postgresql}`,
retained 30 days (`log_retention_days` in `infra/variables.tf`).

### Metrics

The CloudWatch agent publishes `mem_used_percent` and disk `used_percent` under
the `enterprise-java-platform` namespace. `/actuator/metrics` exposes JVM and
HTTP metrics on the host.

**Worth alerting on** (not configured — Tier-3): disk > 80% (Maven caches and
logs grow), `mem_used_percent` > 90%, health check failing 2× consecutively,
CPU credit balance approaching zero on the burstable instance.

---

## 6. Database

### Connect

```bash
ssh ubuntu@<ip>
sudo -u postgres psql appdb
```

### Back up

**There is no automated backup.** Until PostgreSQL moves to RDS, take manual
dumps before anything risky:

```bash
ssh ubuntu@<ip> 'sudo -u postgres pg_dump -Fc appdb' > appdb-$(date +%F).dump
```

Restore:

```bash
scp appdb-2026-08-28.dump ubuntu@<ip>:/tmp/
ssh ubuntu@<ip> 'sudo -u postgres pg_restore -d appdb --clean /tmp/appdb-2026-08-28.dump'
```

### Migrations

Flyway runs at application startup from `src/main/resources/db/migration`.

- Never edit an applied migration — Flyway checksums them and will refuse to start.
- To change something already shipped, add a new `V<n>__description.sql`.
- Check state: `sudo -u postgres psql appdb -c 'SELECT * FROM flyway_schema_history'`.

---

## 7. Scaling

Current shape: one `t3.medium`, app and database sharing the host.

**When p95 rises under normal traffic**, in order of effort:

1. **Vertical.** Change `instance_type` in `infra/udap.auto.tfvars`, deploy.
   Terraform replaces the instance — the EIP persists, **but the on-host database
   does not**. Dump first (§6). Prefer `m7i.large` over a bigger `t3`: burstable
   instances hide their ceiling until credits run out.
2. **Move PostgreSQL to RDS.** Removes DB load from the app host and gets you
   managed backups. This is the highest-value change on this list.
3. **Raise the connection pool.** `spring.datasource.hikari.maximum-pool-size`
   is 10. Raise it only alongside PostgreSQL's `max_connections`.
4. **Horizontal.** Requires RDS (shared state) plus an ALB. At that point the
   GHCR image the pipeline already builds becomes the deployment unit — move to
   ECS rather than managing several VMs.

Re-run the benchmark after any change:

```bash
BASE_URL=http://<ip> APP_AUTH_PASSWORD=<password> k6 run perf/load-test.js
```

---

## 8. Teardown

Use the platform's **Destroy** action, which dispatches the generated
`destroy.yml` with the same Terraform backend configuration.

This **permanently deletes the database**. Take a dump first (§6).

The repository, its secrets and all `.udap/` configuration survive teardown —
redeploying later is just a deploy, with no re-scaffolding needed.

---

## 9. Routine checks

| Cadence | Task |
|---------|------|
| Weekly | Review `dependency-scan` findings; the NVD adds CVEs to code you did not change |
| Weekly | `df -h` on the host — Maven caches and logs grow |
| Monthly | Take and **restore-test** a database dump; an untested backup is not a backup |
| Monthly | Review CloudWatch retention and cost |
| Quarterly | Rotate `JWT_SECRET` and `APP_AUTH_PASSWORD` |
| Quarterly | Bump the Spring Boot patch version and redeploy |
