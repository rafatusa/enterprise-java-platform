# Architecture

Three views: what the system **is** (architecture), what happens during a
**request**, and what happens during a **deployment**.

The canonical machine-readable source is [`.udap/architecture.d2`](../.udap/architecture.d2),
which is cross-checked against `infra/` by the project validator. The diagrams
below are the human-facing elaboration.

---

## 1. System architecture

```d2
direction: down

client: API Client / Browser {
  shape: person
}

aws: AWS us-east-1 {
  eip: Elastic IP {
    shape: hexagon
  }

  sg: "Security Group\n22 / 80 / 443 inbound" {
    shape: hexagon
  }

  ec2: "EC2 t3.medium — Ubuntu 22.04" {
    nginx: "Nginx :80\nreverse proxy"
    app: "Spring Boot :8080\nsystemd, appuser"
    db: "PostgreSQL 16\n127.0.0.1:5432" {
      shape: cylinder
    }

    nginx -> app: proxy_pass
    app -> db: JDBC
  }

  iam: "IAM Role\ninstance profile" {
    shape: hexagon
  }

  logs: "CloudWatch Logs\napp / nginx / postgres" {
    shape: page
  }
}

ghcr: "GHCR\ncontainer registry" {
  shape: cylinder
}

client -> aws.eip: HTTPS
aws.eip -> aws.ec2.nginx: :80
aws.sg -> aws.ec2: allows
aws.iam -> aws.ec2: grants logs:PutLogEvents
aws.ec2 -> aws.logs: CloudWatch agent
ghcr -> aws.ec2: image published (audit trail)
```

**Design decisions and their trade-offs.**

| Decision | Why | What it costs |
|----------|-----|---------------|
| Single EC2 instance | Tier-2 scope, one workload, lowest operational surface | No HA; instance replacement is an outage |
| PostgreSQL on-host | The request was for PostgreSQL, not RDS; keeps the benchmark measuring the app rather than cross-AZ latency | No managed backups or PITR |
| Nginx in front | App binds loopback, so the proxy is the sole entry point; also gives rate limiting and gzip | One more process to configure |
| `t3.medium` | 200 VUs for 15 min exhausts `t3.small` CPU credits and fails p95 for infrastructure reasons | ~$30/mo instead of ~$15 |
| Default VPC | The probe found one; building a VPC adds no isolation for a single public web host | No private subnet placement |
| Puppet + Ansible | Explicit requirement; the split is durable machine state vs. per-release actions | Two tools to know |

**Why the image is published but not deployed from.** The pipeline builds,
scans and pushes a container image to GHCR, but the EC2 host runs the jar under
systemd. The image is the portable, scanned artifact of record and the migration
path to ECS/EKS; the VM deployment is what the target calls for today. Running
both from one build keeps them honest.

---

## 2. Request sequence

```d2
shape: sequence_diagram

client: Client
nginx: Nginx
filter: JwtAuthenticationFilter
ctrl: TaskController
svc: TaskService
repo: TaskRepository
db: PostgreSQL

client -> nginx: "POST /api/v1/auth/login"
nginx -> filter: "proxy_pass 127.0.0.1:8080"
filter -> ctrl: "no Authorization header — anonymous, permitted"
ctrl -> ctrl: "bcrypt compare"
ctrl -> client: "200 { token, expiresIn }"

client -> nginx: "GET /api/v1/tasks\nAuthorization: Bearer ..."
nginx -> filter: proxy_pass
filter -> filter: "resolveSubject(token)"
filter -> ctrl: "authenticated (ROLE_USER)"
ctrl -> svc: "findAll(status)"
svc -> repo: "findAll() / findByStatus()"
repo -> db: SELECT
db -> repo: rows
repo -> svc: "List<Task>"
svc -> ctrl: "List<TaskResponse>"
ctrl -> client: "200 [ ... ]"

client -> nginx: "PATCH /tasks/{id}/status?value=OPEN"
nginx -> filter: proxy_pass
filter -> ctrl: authenticated
ctrl -> svc: "transition(id, OPEN)"
svc -> repo: findById
repo -> db: SELECT
db -> repo: "task (status=DONE)"
svc -> svc: "DONE is terminal — reject"
svc -> ctrl: IllegalStateException
ctrl -> client: "409 Conflict"
```

An invalid or absent token never reaches the controller: the filter leaves the
context anonymous and Spring Security's entry point returns `401`.

---

## 3. Deployment sequence

```d2
shape: sequence_diagram

ci: GitHub Actions
tf: Terraform
ec2: EC2 Instance
puppet: Puppet
ansible: Ansible
k6: k6

ci -> ci: "build, format, static analysis"
ci -> ci: "tests + JaCoCo gate (90/85)"
ci -> ci: "PIT mutation gate (70)"
ci -> ci: "gitleaks, semgrep, OWASP, Trivy, SBOM"
ci -> ci: "docker build + Trivy image scan"
ci -> ci: "push to GHCR"

ci -> tf: "fmt, validate, plan"
ci -> tf: "apply"
tf -> ec2: "instance, EIP, SG, IAM, log groups"
tf -> ci: "terraform output public_ip"

ci -> puppet: "puppet-bootstrap.yml"
puppet -> ec2: "packages, appuser, layout"
puppet -> ec2: "SSH + sysctl hardening"
puppet -> ec2: "CloudWatch agent"

ci -> ansible: "site.yml"
ansible -> ec2: "PostgreSQL db + role"
ansible -> ec2: "build jar, publish release"
ansible -> ec2: "previous -> outgoing release"
ansible -> ec2: ".env (0640, no_log)"
ansible -> ec2: "current -> new release"
ansible -> ec2: "restart, Flyway migrates"
ansible -> ec2: "nginx vhost + reload"

ci -> ec2: "health + 7 smoke checks"
ec2 -> ci: "PASS"

ci -> k6: "200 VUs, 15 min"
k6 -> ec2: load
k6 -> ci: "p95, error rate, throughput"
ci -> ci: "GitHub Release + all reports"
```

**On failure at the verification step**, `verify-with-rollback.sh` runs
`ansible/rollback.yml`: `current` is repointed at `previous`, the service is
restarted, and health is re-checked. The stage then exits non-zero regardless of
whether the rollback succeeded — a rolled-back deploy is still a failed deploy.

---

## 4. Deployment topology

```d2
direction: right

gh: GitHub {
  repo: "Repository\nmain branch"
  actions: "Actions runner\nubuntu-latest"
  ghcr: "GHCR" {
    shape: cylinder
  }
  releases: "Releases\n+ report artifacts" {
    shape: page
  }
}

s3: "S3\nterraform.tfstate" {
  shape: cylinder
}

host: "EC2 t3.medium — Ubuntu 22.04" {
  systemd: "systemd: app.service"
  nginx: "systemd: nginx"
  pg: "systemd: postgresql"
  cw: "CloudWatch agent"

  releases: "/opt/app/releases/<sha>/" {
    shape: page
  }
  current: "/opt/app/current ->"
  previous: "/opt/app/previous ->"

  current -> releases: symlink
  previous -> releases: "symlink (rollback)"
  systemd -> current: "java -jar"
}

cwl: "CloudWatch Logs" {
  shape: page
}

gh.repo -> gh.actions: workflow_dispatch
gh.actions -> s3: "state (init -reconfigure)"
gh.actions -> gh.ghcr: "push image"
gh.actions -> host: "SSH: puppet + ansible"
gh.actions -> gh.releases: "publish reports"
host.cw -> cwl: "app / nginx / postgres"
```

### Ports

| Port | Exposure | Purpose |
|------|----------|---------|
| 22 | Public (key auth only) | CI deployment over SSH |
| 80 | Public | Nginx — the only application entry point |
| 443 | Open, unused | Reserved for TLS |
| 8080 | `127.0.0.1` only | Spring Boot, reachable solely via nginx |
| 5432 | `127.0.0.1` only | PostgreSQL |

### State

| State | Where | Survives instance replacement |
|-------|-------|-------------------------------|
| Terraform state | S3, key `<project>/terraform.tfstate` | Yes |
| Application data | PostgreSQL on the instance's EBS volume | **No** |
| Releases | `/opt/app/releases` on EBS | No — rebuilt each deploy |
| Logs | CloudWatch Logs | Yes |
| SSH keypair | AWS SSM, platform-managed | Yes |

The second row is the significant one: **application data does not survive
instance replacement.** That is the accepted trade-off of an on-host database at
this tier, and the reason RDS is the first recommended upgrade.
