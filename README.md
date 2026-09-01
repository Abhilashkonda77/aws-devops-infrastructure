# DevOps Portfolio Project — GitHub Actions -> ECR -> ECS Fargate -> RDS

A complete, runnable, end-to-end DevOps reference project: a containerized
Node.js app, deployed via GitHub Actions CI/CD to Amazon ECS Fargate behind
an Application Load Balancer, backed by RDS PostgreSQL, provisioned
entirely with Terraform, observed with CloudWatch.

## Table of contents

- [Architecture](#architecture)
- [Technology choices](#technology-choices)
- [Repository structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Configuration — values you must customize](#configuration--values-you-must-customize)
- [Quickstart](#quickstart)
- [Application — local development](#application--local-development)
- [Docker](#docker)
- [Bootstrap — Terraform remote state](#bootstrap--terraform-remote-state)
- [Terraform — deploying infrastructure](#terraform--deploying-infrastructure)
- [ECR](#ecr)
- [GitHub Actions & OIDC setup](#github-actions--oidc-setup)
- [Staging deployment](#staging-deployment)
- [Production deployment](#production-deployment)
- [Monitoring](#monitoring)
- [Testing](#testing)
- [Validation checklist](#validation-checklist)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Cost considerations](#cost-considerations)
- [Security considerations](#security-considerations)
- [Assumptions & limitations](#assumptions--limitations)
- [Future improvements](#future-improvements)
- [Concepts explained](#concepts-explained)
- [Interview questions](#interview-questions)

## Architecture

```
GitHub -> GitHub Actions (OIDC) -> Amazon ECR -> Amazon ECS Fargate
   -> Application Load Balancer -> Container -> Amazon RDS PostgreSQL
```

```
VPC
├── Public Subnet AZ-1     -> Application Load Balancer
├── Public Subnet AZ-2     -> Application Load Balancer, NAT Gateway
├── Private App Subnet AZ-1 -> ECS Fargate
├── Private App Subnet AZ-2 -> ECS Fargate
└── Private DB Subnet(s)    -> RDS PostgreSQL
```

Full explanation of every module, the request path, and design trade-offs:
see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Technology choices

| Layer | Choice | Why |
|---|---|---|
| IaC | Terraform, `~> 5.60` AWS provider | Explicit state, cloud-agnostic, industry standard |
| Compute | ECS Fargate | No servers/nodes to manage; simplest path to "run a container in production" on AWS |
| CI/CD | GitHub Actions + OIDC | No stored AWS keys; native to GitHub |
| App | Node.js 20 + Express | Minimal, fast-starting, easy to read regardless of daily language |
| DB | RDS PostgreSQL 16 | Managed, encrypted, Multi-AZ capable |
| Monitoring | CloudWatch (dashboards, alarms, logs) | Native, no extra infra to run |

## Repository structure

```
project/
├── README.md
├── .gitignore
├── application/              # Node.js/Express sample app
├── docker/                   # Dockerfile + .dockerignore
├── infrastructure/
│   ├── bootstrap/            # One-time: creates the Terraform state S3 bucket
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ecs/
│   │   ├── rds/
│   │   ├── alb/
│   │   ├── ecr/
│   │   ├── iam/
│   │   └── cloudwatch/
│   └── envs/
│       ├── staging/
│       └── prod/
├── monitoring/                # Notes on dashboards/alarms (Terraform-managed)
├── scripts/
│   ├── bootstrap.sh
│   ├── smoke-test.sh
│   └── cleanup.sh
├── docs/
│   ├── ARCHITECTURE.md
│   └── SECURITY.md
└── .github/workflows/ci-cd.yml
```

## Prerequisites

- AWS account with permissions to create VPCs, ECS, RDS, ALB, ECR, IAM, S3,
  KMS, CloudWatch, SNS resources
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.10.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2, configured (`aws configure` or SSO)
- [Docker](https://docs.docker.com/get-docker/)
- Node.js >= 20 (for local app development)
- A GitHub repository you control (for the Actions/OIDC portion)
- `jq` (used by the CI/CD workflow's task-definition update steps; install locally too if you want to run those commands by hand)

## Configuration — values you must customize

| Value | Where | Notes |
|---|---|---|
| AWS region | `envs/*/variables.tf` (`aws_region`), `.github/workflows/ci-cd.yml` (`AWS_REGION`) | Default `us-east-1` |
| AWS account ID | Embedded implicitly via the state bucket name | Used to make the bucket name globally unique |
| State bucket name | `bootstrap/terraform.tfvars`, `envs/*/backend.tf`, `envs/prod/providers.tf` | Must match everywhere after bootstrap |
| GitHub org/repo | `envs/*/terraform.tfvars` (`github_org`, `github_repo`) | Used in the OIDC trust policy |
| Domain/DNS | Not used — HTTP-only ALB, see `docs/SECURITY.md` | Add if you want HTTPS |
| Database config | `envs/*/variables.tf` (`db_instance_class`, `db_multi_az`, etc.) | Password is never set here — RDS-managed |
| GitHub Actions variables | Repo Settings > Environments/Variables | `AWS_DEPLOY_ROLE_ARN_STAGING`, `AWS_DEPLOY_ROLE_ARN_PROD`, `STAGING_ALB_URL`, `PROD_ALB_URL` |
| GitHub Actions secrets | None required | OIDC removes the need for stored AWS secrets |
| IAM | `envs/*/terraform.tfvars` | `github_org`/`github_repo` drive the OIDC trust condition |

Never commit real values for any of the above — copy each `*.example` file
and fill in the copy, which `.gitignore` already excludes.

## Quickstart

```bash
git clone <your-repo-url> && cd project

# 1. Bootstrap remote state (one time)
cp infrastructure/bootstrap/terraform.tfvars.example infrastructure/bootstrap/terraform.tfvars
# edit state_bucket_name to something globally unique
./scripts/bootstrap.sh

# 2. Point staging/prod backends at that bucket (edit the 'bucket' value in
#    infrastructure/envs/staging/backend.tf, infrastructure/envs/prod/backend.tf,
#    and infrastructure/envs/prod/providers.tf's terraform_remote_state block)

# 3. Deploy staging
cd infrastructure/envs/staging
cp terraform.tfvars.example terraform.tfvars   # fill in github_org / github_repo
terraform init
terraform apply

# 4. Wire up GitHub Actions (see "GitHub Actions & OIDC setup" below), push to main
```

## Application — local development

```bash
cd application
cp .env.example .env
npm install
npm start
# in another terminal:
curl http://localhost:3000/health
curl http://localhost:3000/
```

Runs without a database (`/health` reports `"database": "skipped"`). Set
`DB_HOST` in `.env` to test against a local/remote Postgres instance.

## Docker

```bash
# From the repository root (build context = repo root, Dockerfile is under docker/)
docker build -f docker/Dockerfile -t devops-portfolio-app:local .

docker run --rm -p 3000:3000 \
  -e APP_ENV=local \
  devops-portfolio-app:local

curl http://localhost:3000/health
```

The image runs as a non-root user (`appuser`, UID 1001) and has a built-in
`HEALTHCHECK` that calls `/health`.

## Bootstrap — Terraform remote state

Run once, before anything else:

```bash
cp infrastructure/bootstrap/terraform.tfvars.example infrastructure/bootstrap/terraform.tfvars
# edit state_bucket_name (globally unique, e.g. include your AWS account ID)
./scripts/bootstrap.sh
```

This creates an encrypted, versioned S3 bucket for Terraform state. State
locking uses Terraform's native S3 locking (`use_lockfile = true`,
Terraform >= 1.10) — no DynamoDB table is created or required.

After it completes, update the `bucket` value in:
- `infrastructure/envs/staging/backend.tf`
- `infrastructure/envs/prod/backend.tf`
- `infrastructure/envs/prod/providers.tf` (`terraform_remote_state` block)

## Terraform — deploying infrastructure

Staging must be applied before prod (prod reads staging's ECR repo URL and
GitHub OIDC provider ARN via `terraform_remote_state`).

```bash
cd infrastructure/envs/staging
cp terraform.tfvars.example terraform.tfvars    # set github_org / github_repo
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Repeat under `infrastructure/envs/prod` once staging exists.

The very first apply deploys the ECS service with a placeholder image tag
(`bootstrap-placeholder`, which does not exist in ECR yet) — the ECS
service will show 0 running tasks until GitHub Actions pushes a real image
and updates the service. This is expected: infrastructure and application
deployment are deliberately decoupled.

## ECR

Created once, in the staging stack, and reused by prod. Images are tagged
with the 12-character Git commit SHA (see `.github/workflows/ci-cd.yml`).
The lifecycle policy expires untagged images after 3 days and keeps only
the most recent 20 tagged images. Tags are immutable
(`image_tag_mutability = "IMMUTABLE"`) — a given SHA can never be
overwritten, only superseded by a new tag.

## GitHub Actions & OIDC setup

1. Apply `envs/staging` and `envs/prod` (creates the OIDC provider, once,
   in staging, and a deploy role in each environment).
2. Get the role ARNs:
   ```bash
   cd infrastructure/envs/staging && terraform output github_actions_role_arn
   cd ../prod && terraform output github_actions_role_arn
   ```
3. In the GitHub repo: **Settings > Environments**, create `staging` and
   `production`. On `production`, add required reviewers (this is the
   manual approval gate).
4. In each environment (or repo-level, if you prefer), add **Variables**:
   - `AWS_DEPLOY_ROLE_ARN_STAGING` — staging's role ARN
   - `AWS_DEPLOY_ROLE_ARN_PROD` — prod's role ARN
   - `STAGING_ALB_URL` — `http://<staging alb_dns_name output>`
   - `PROD_ALB_URL` — `http://<prod alb_dns_name output>`
5. No AWS secrets are needed — OIDC handles authentication.

## Staging deployment

Push to `main` (or merge a PR): tests run, image builds and pushes to ECR,
staging's ECS service updates automatically, then a smoke test runs
against the staging ALB. No manual step.

## Production deployment

Same pipeline run continues past the staging smoke test into the
`production` GitHub Environment, which pauses for a required reviewer's
approval before deploying the same image to prod and smoke-testing it.

## Monitoring

Two CloudWatch dashboards per environment (see
`infrastructure/modules/cloudwatch/main.tf`):

- **Infrastructure**: ECS CPU/memory, running vs desired task count, ALB
  request count, ALB 4xx/5xx, target health.
- **Application**: request count, target 5xx, latency (avg + p99),
  healthy-target count, a live Logs Insights query for recent error-level
  log lines.

Alarms (all notify an SNS topic; add `sns_alarm_email` in `terraform.tfvars`
to get emailed — you must confirm the subscription from your inbox):
ECS CPU high, ECS memory high, running tasks below desired, ALB 5xx high,
ALB unhealthy hosts, ALB p99 latency high, RDS CPU high, RDS free storage
low.

Get dashboard URLs from Terraform output: `terraform output
infrastructure_dashboard_url` / `application_dashboard_url`.

## Testing

```bash
cd application
npm install
npm test
```

Also run automatically in CI on every PR and push to `main`. Post-deploy,
`scripts/smoke-test.sh <base-url>` verifies `/health` and `/` return 200,
retrying for a couple of minutes to absorb normal deployment lag.

## Validation checklist

Directory tree: see [Repository structure](#repository-structure) above.

```bash
# Installation prerequisites
terraform -version   # >= 1.10.0
aws --version         # v2
docker --version
node --version         # >= 20

# Local app test
cd application && npm install && npm test

# Docker build/test
docker build -f docker/Dockerfile -t devops-portfolio-app:local .
docker run --rm -p 3000:3000 devops-portfolio-app:local &
curl -f http://localhost:3000/health

# Terraform formatting & validation (run in bootstrap/ and each envs/* dir)
terraform fmt -check -recursive
terraform validate

# Terraform plan
terraform plan

# Bootstrap procedure
./scripts/bootstrap.sh

# Infrastructure deployment sequence
# staging first, then prod (prod reads staging's remote state)

# ECR procedure
aws ecr describe-repositories --repository-names devops-portfolio-app

# CI/CD setup
# see "GitHub Actions & OIDC setup" above

# Staging / production deployment
# push to main; approve the production gate in GitHub

# Smoke testing
./scripts/smoke-test.sh http://<alb-dns-name>

# CloudWatch verification
aws cloudwatch list-dashboards
aws cloudwatch describe-alarms --alarm-name-prefix devops-portfolio

# Cleanup procedure
./scripts/cleanup.sh staging
./scripts/cleanup.sh prod
```

## Troubleshooting

| Problem | Fix |
|---|---|
| **Terraform state** locked / "Error acquiring the state lock" | Someone else (or a crashed run) holds the lock. Confirm no other apply is running, then `terraform force-unlock <LOCK_ID>` (ID is in the error message). |
| **Terraform state** bucket not found | Bootstrap wasn't applied, or `backend.tf`'s `bucket` value doesn't match the actual bucket name. Re-check both. |
| **AWS authentication** fails locally | Run `aws sts get-caller-identity` to confirm your CLI identity; re-run `aws configure` or refresh SSO (`aws sso login`). |
| **AWS authentication** fails in GitHub Actions | Confirm the repo Environment's `AWS_DEPLOY_ROLE_ARN_*` variable is set and the role's trust policy `sub` condition matches `repo:<org>/<repo>:*` exactly. |
| **VPC routing**: app subnets have no internet access | Check the NAT Gateway is `available` (`aws ec2 describe-nat-gateways`) and the app route table has a `0.0.0.0/0 -> nat-...` route. |
| **NAT Gateway** stuck in "pending" or tasks can't pull images | NAT takes a few minutes to provision on first apply; ECS tasks started too early will fail — retry the deployment after NAT is `available`. |
| **RDS connectivity** refused from ECS tasks | Confirm the RDS security group's ingress rule references the ECS tasks security group ID (not a CIDR), and that both are in the same VPC. |
| **ECS task startup** failures (`STOPPED` immediately) | `aws ecs describe-tasks --cluster <cluster> --tasks <task-arn>` — check `stoppedReason`. Common causes: bad image tag (doesn't exist in ECR yet), missing Secrets Manager permission, container health check failing. |
| **ECR image pull** `CannotPullContainerError` | Task execution role missing ECR permissions (should come from the `AmazonECSTaskExecutionRolePolicy` managed policy — verify it's attached), or the image tag doesn't exist. |
| **IAM permissions** `AccessDenied` on `iam:PassRole` | The GitHub Actions deploy role's `PassRole` statement is conditioned on `iam:PassedToService = ecs-tasks.amazonaws.com` — make sure you're passing the task/execution roles, not some other role. |
| **ALB health checks** failing (targets unhealthy) | Confirm the container actually listens on `app_container_port`, `/health` returns 200 within the configured timeout, and the ECS security group allows the ALB security group on that port. |
| **GitHub OIDC** "no identity-based policy allows the sts:AssumeRoleWithWebIdentity action" | The trust policy's `sub` condition doesn't match your repo, or `create_oidc_provider` was set `true` in more than one environment (only one OIDC provider is allowed per account — see `infrastructure/modules/iam/main.tf`). |
| **GitHub Actions** workflow doesn't trigger | Confirm the workflow file is on the default branch and the `on:` triggers match your branch name (`main`). |
| **CloudWatch logs** empty | Confirm the task definition's `awslogs-group` matches an existing log group, and the task execution role has `logs:CreateLogStream`/`logs:PutLogEvents` on it (granted in the `iam` module). |
| **Docker** build fails on `npm install` | Make sure you're building from the repo root with `-f docker/Dockerfile` so the `COPY application/...` paths resolve. |

## Cleanup

```bash
./scripts/cleanup.sh staging
./scripts/cleanup.sh prod
```

Destroys the VPC, ALB, ECS cluster/service, RDS instance, CloudWatch
resources, and the environment's IAM roles for that environment. Requires
typing the environment name to confirm. Does **not** delete the Terraform
state bucket (`infrastructure/bootstrap`) — destroy that manually only if
you're completely done with the project:

```bash
cd infrastructure/bootstrap
terraform destroy   # bucket has prevent_destroy = true; remove that lifecycle block first if you really mean it
```

Production RDS takes a final snapshot on destroy (`skip_final_snapshot =
false`) — it is **not** deleted by `cleanup.sh` and keeps costing storage
until you remove it by hand (`aws rds delete-db-snapshot`).

## Cost considerations

Resources that incur ongoing charges (approximate, `us-east-1`, per
environment — staging + prod roughly double this):

| Resource | Approx. cost driver |
|---|---|
| **NAT Gateway** | ~$0.045/hr + data processing — the single largest fixed cost in this project |
| **RDS** (`db.t4g.micro`/`small`) | Instance-hours + storage; Multi-AZ (prod) roughly doubles it |
| **ALB** | ~$0.0225/hr + LCU-based request charges |
| **ECS Fargate** | Per-vCPU/memory-second while tasks run; staging default is 2 tasks x 0.25 vCPU/0.5GB |
| **CloudWatch** | Log ingestion/storage, custom dashboards beyond the free tier, alarm-minutes |

None of these are free-tier-eligible indefinitely. **Run
`./scripts/cleanup.sh` when you're done testing** to stop the meter — the
single NAT Gateway per environment is usually the biggest line item if you
leave the stack running idle.

## Security considerations

See [`docs/SECURITY.md`](docs/SECURITY.md) for the full list of applied
controls and the deliberately-out-of-scope items (HTTPS/ACM, WAF, VPC Flow
Logs, secret rotation schedule) with reasoning for each.

## Assumptions & limitations

- No domain name or ACM certificate is assumed — the ALB is HTTP-only.
  Adding HTTPS is a documented, isolated change (see `docs/SECURITY.md`).
- The sample application has no real business logic on purpose — it exists
  to demonstrate the deployment pipeline, not to be a product.
- A single NAT Gateway is shared across both AZs for cost reasons; this is
  a single point of failure for outbound connectivity (inbound traffic via
  the ALB is unaffected by NAT Gateway failure).
- `terraform_remote_state` is used for prod to read staging's outputs
  (ECR repo, OIDC provider). This creates a soft ordering dependency:
  staging must exist before prod can plan successfully.
- CI/CD assumes a single AWS account for both staging and prod. Separate
  AWS accounts per environment (a common enterprise pattern) would need
  per-account OIDC providers/roles and cross-account ECR permissions.

## Future improvements

- HTTPS via ACM + Route 53, with an HTTP->HTTPS redirect
- AWS WAF in front of the ALB
- Separate AWS accounts per environment with cross-account image promotion
- Blue/green deploys via CodeDeploy instead of ECS rolling updates
- VPC Flow Logs + GuardDuty for network/threat visibility
- Automated rollback on failed prod smoke test
- Integration tests against a real ephemeral database (e.g. via testcontainers)

## Concepts explained

- **VPC** — an isolated virtual network in AWS where you control the IP
  range, subnets, and routing. Everything in this project lives inside one.
- **Public vs private subnet** — a subnet is "public" if its route table
  sends `0.0.0.0/0` traffic to an Internet Gateway (resources can have
  public IPs and be reached from the internet). A "private" subnet instead
  routes outbound traffic through a NAT Gateway (or nowhere, for the DB
  subnets here) — nothing inside can be reached directly from the internet.
- **NAT Gateway** — a managed AWS service that lets resources in private
  subnets initiate outbound internet connections (e.g. pulling from ECR
  over the internet, calling AWS APIs) without being reachable from the
  internet themselves.
- **Security groups** — stateful, instance/ENI-level virtual firewalls.
  This project chains them (ALB SG -> ECS SG -> RDS SG) instead of using
  raw IP ranges, so the network topology is self-documenting in Terraform.
- **RDS** — AWS's managed relational database service; handles patching,
  backups, and (optionally) Multi-AZ failover for you.
- **ECS** — AWS's container orchestration service: schedules containers
  ("tasks") onto compute, keeps the desired count running, integrates with
  the ALB for load balancing and health-based replacement.
- **Fargate** — the "serverless" launch type for ECS: you specify CPU/memory
  per task and AWS runs it without you managing any EC2 instances.
- **ALB (Application Load Balancer)** — Layer 7 load balancer; routes HTTP
  traffic to healthy targets in a target group, terminates connections,
  and is this project's only public entry point.
- **ECR** — AWS's managed Docker registry; stores the images this project
  builds and deploys, with vulnerability scanning and lifecycle policies.
- **IAM** — AWS's identity and access system: who (roles, OIDC-federated
  identities) can do what (actions) to which resources.
- **Task execution role vs task role** — the execution role is used *by
  ECS itself* to pull the image and fetch secrets/write logs on the task's
  behalf; the task role is assumed *by your application code* inside the
  container for any AWS API calls it makes. Separating them means the
  container's own AWS permissions are independent of, and typically far
  narrower than, what ECS needs to launch it.
- **Terraform modules** — reusable, parameterized Terraform configurations
  (this project's `vpc`, `ecs`, `rds`, `alb`, `ecr`, `iam`, `cloudwatch`)
  called from thin environment-specific root configurations.
- **Terraform remote state** — storing the state file (which maps
  configuration to real resource IDs) somewhere shared and durable (S3
  here) instead of a local file, so teams and CI can collaborate on the
  same infrastructure.
- **State locking** — preventing two concurrent `terraform apply` runs from
  corrupting the same state file. This project uses Terraform's native S3
  locking (conditional writes) instead of a separate DynamoDB table.
- **GitHub OIDC** — GitHub Actions can present a short-lived, cryptographically
  signed identity token to AWS STS, which exchanges it for temporary AWS
  credentials — no stored AWS access keys in GitHub at all.
- **CI/CD** — Continuous Integration (run tests on every change) and
  Continuous Deployment (automatically ship changes that pass), implemented
  here as the GitHub Actions workflow in `.github/workflows/ci-cd.yml`.
- **Docker** — packages the application and its runtime dependencies into a
  portable, immutable image, built once and run identically in every
  environment.
- **CloudWatch** — AWS's native observability service: this project uses it
  for container logs, custom dashboards, and metric-based alarms.

## Interview questions

**Infrastructure & networking**

1. **Why does this project use two Availability Zones instead of one?**
   For fault tolerance — if one AZ has an outage, the ALB, ECS tasks, and
   (with Multi-AZ RDS) the database can still serve traffic from the other.
2. **Why is there only one NAT Gateway instead of one per AZ?**
   Cost — NAT Gateways bill hourly plus data processing. A single shared
   NAT is a documented trade-off: outbound-only traffic has a single point
   of failure, but inbound traffic via the ALB is unaffected.
3. **What would happen to running ECS tasks if the NAT Gateway went down?**
   Existing connections would be unaffected, but tasks needing new outbound
   connections (e.g. calling an external API) would fail; inbound traffic
   via the ALB to already-running healthy tasks continues to work.
4. **Why do database subnets have no route to the internet at all, not even
   via NAT?**
   Defense in depth — the database should never need to initiate outbound
   internet connections, so removing the route entirely closes off an
   entire class of exfiltration/compromise scenarios even if the security
   group were misconfigured.
5. **Why do security groups reference other security groups instead of CIDR
   blocks?**
   It's self-documenting and safer under change — if the ECS tasks' subnet
   CIDR ever changes, the RDS security group rule (referencing the ECS SG
   ID) doesn't need to change with it.
6. **What's the difference between a security group and a network ACL, and
   why doesn't this project use NACLs?**
   Security groups are stateful (return traffic auto-allowed) and attach to
   resources; NACLs are stateless and attach to subnets. This project relies
   on SGs alone for simplicity — NACLs would add a second, easy-to-misconfigure
   layer without a specific requirement driving it here.

**Compute & containers**

7. **Why Fargate instead of EC2 launch type for ECS?**
   No servers to patch or scale manually; you pay per task resource
   request instead of per underlying instance, which fits a small
   portfolio-scale workload better.
8. **What does `target_type = "ip"` on the target group do, and why is it
   required here?**
   Registers targets by ENI IP rather than EC2 instance ID — required for
   Fargate, since tasks don't correspond to a registerable EC2 instance.
9. **What is the ECS deployment circuit breaker, and what does this project
   set it to do?**
   It detects a deployment that can't reach a steady state (e.g. new tasks
   keep failing health checks) and stops it automatically; this project
   sets `rollback = true` so it also reverts to the last working task
   definition.
10. **Why does the ECS service ignore changes to `task_definition` and
    `desired_count` in its `lifecycle` block?**
    Both are updated by the CI/CD pipeline (`aws ecs update-service` with a
    new revision) between Terraform applies. Without `ignore_changes`,
    the next `terraform apply` would revert CI/CD's deploy back to
    whatever tag/count is in the `.tf` files.
11. **Why does the Dockerfile use a multi-stage build?**
    To keep the final runtime image small and free of build-time-only
    artifacts (no dev dependencies, no build tooling) — smaller images
    pull faster and have a smaller attack surface.
12. **Why run the container as a non-root user?**
    Limits blast radius if the application process is compromised — a
    non-root user inside the container can't, for example, modify files
    owned by root or exploit certain container-escape vectors as easily.
13. **Why use `node server.js` directly as `CMD` instead of `npm start`?**
    `npm` wraps the process and doesn't always forward signals like
    `SIGTERM` cleanly to the child process; running `node` directly as PID 1
    ensures the app's own signal handlers (used for graceful shutdown) fire.

**Database**

14. **Why is the RDS password never set in Terraform?**
    `manage_master_user_password = true` has RDS generate and store the
    password in Secrets Manager directly — it never appears in `.tf` files,
    `terraform plan` output, or state in plaintext.
15. **How does the ECS task get the database password without it being in
    the task definition in plaintext?**
    The task definition's `secrets` block references the Secrets Manager
    ARN; ECS injects the resolved value as an environment variable at
    container start — the task execution role needs
    `secretsmanager:GetSecretValue` on that ARN, which the `iam` module
    grants.
16. **Why is Multi-AZ enabled for prod but not staging?**
    Cost/availability trade-off — Multi-AZ roughly doubles RDS cost for
    automatic failover, which is worth it in prod but not for a
    disposable/testing staging environment.

**CI/CD & IAM**

17. **Why OIDC instead of storing `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
    as GitHub secrets?**
    OIDC credentials are short-lived and scoped per workflow run — nothing
    long-lived to leak, rotate, or accidentally commit.
18. **What does the `sub` condition in the OIDC trust policy do?**
    Restricts which GitHub repo (and optionally branch/environment) is
    allowed to assume the role — without it, any GitHub Actions workflow
    anywhere could potentially assume it.
19. **Why is only one GitHub OIDC provider created across both
    environments?**
    AWS only allows one OIDC provider per unique URL per account; creating
    it twice would error, so it's created once (in staging) and referenced
    by ARN in prod (`create_oidc_provider = false`).
20. **What is the difference between the ECS task execution role and the
    task role, concretely, in this project's IAM module?**
    The execution role can read the DB secret and write logs — used by
    the ECS agent to launch the task. The task role has no extra
    permissions here since the sample app makes no AWS API calls itself;
    it exists as the place to add such permissions later without touching
    the execution role.
21. **Why does the GitHub Actions deploy role's IAM policy scope
    `iam:PassRole` with a condition instead of just allowing it broadly?**
    So the deploy role can only hand off the two specific ECS roles it
    needs to, and only when the receiving service is `ecs-tasks.amazonaws.com`
    — it can't be used to pass, say, an admin role to some other service.
22. **Why does production require a manual approval step but staging
    doesn't?**
    Staging deploys are low-risk and meant to be fast-feedback; production
    deploys affect real users, so a GitHub Environment with required
    reviewers adds a deliberate human checkpoint before the same image
    is promoted.
23. **Why is the same image promoted from staging to prod rather than
    rebuilt for prod?**
    Guarantees what was smoke-tested in staging is bit-for-bit what runs
    in production — rebuilding could introduce drift (different base image
    layer, different dependency resolution at build time).
24. **Why is rollback a manual step instead of automated on smoke-test
    failure?**
    A failing prod smoke test is exactly the moment you want a human to
    look at what's happening, not an automated system silently reverting
    and potentially masking a real problem.

**Terraform**

25. **What problem does Terraform remote state solve that local state
    doesn't?**
    Local state lives on one machine — it doesn't support team
    collaboration or CI-driven applies, and it's easy to lose. Remote
    state (S3 here) is shared, durable, and versioned.
26. **What is state locking for, and how does this project implement it?**
    Prevents two concurrent applies from writing to the state file at the
    same time, which can corrupt it. This project uses Terraform's native
    S3 locking (`use_lockfile = true`, via S3 conditional writes,
    Terraform >= 1.10) instead of a separate DynamoDB lock table.
27. **Why does the bootstrap stack use local state instead of remote
    state?**
    It creates the very S3 bucket that remote state would live in — it
    can't depend on infrastructure it hasn't created yet.
28. **Why is `prevent_destroy = true` set on the Terraform state bucket?**
    To make it much harder to accidentally destroy the bucket holding
    every other stack's state via a stray `terraform destroy` in the
    bootstrap directory.
29. **How does `envs/prod` get the ECR repository URL without redefining
    the `ecr` module?**
    A `terraform_remote_state` data source reads staging's state file
    directly from S3 and pulls the `ecr_repository_url` output — the ECR
    module is only instantiated once, in staging.

**Monitoring**

30. **Why are there two separate CloudWatch dashboards instead of one?**
    Separation of concerns: "Infrastructure" (ECS/ALB resource health)
    is typically an ops/platform concern, while "Application" (request
    rate, error rate, latency, live error logs) is more relevant
    day-to-day to whoever owns the application code — splitting them
    keeps each dashboard focused and readable.

---

Questions or issues? Check [Troubleshooting](#troubleshooting) first, then
review the relevant module's comments in `infrastructure/modules/`.
