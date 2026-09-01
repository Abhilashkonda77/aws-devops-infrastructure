# Architecture

## Overview

```
GitHub
  |
  v
GitHub Actions  (OIDC -> AWS, no long-lived keys)
  |
  v
Amazon ECR  (image tagged with Git commit SHA)
  |
  v
Amazon ECS Fargate  (staging, then production)
  |
  v
Application Load Balancer  (public entry point)
  |
  v
Containerized Node.js application
  |
  v
Amazon RDS PostgreSQL  (private, encrypted)
```

## Network layout

Each environment (staging, prod) gets its own VPC, spread across 2
Availability Zones:

```
VPC (10.0.0.0/16 staging, 10.1.0.0/16 prod)
├── Public Subnet AZ-1     -> ALB (ALB spans both public subnets)
├── Public Subnet AZ-2     -> ALB, NAT Gateway (single shared NAT)
├── Private App Subnet AZ-1 -> ECS Fargate tasks
├── Private App Subnet AZ-2 -> ECS Fargate tasks
├── Private DB Subnet AZ-1  -> RDS PostgreSQL
└── Private DB Subnet AZ-2  -> RDS PostgreSQL (standby, if Multi-AZ)
```

Traffic flow: internet -> ALB (public subnets) -> ECS tasks (private app
subnets, security group only allows the ALB's security group in) -> RDS
(private db subnets, security group only allows the ECS tasks' security
group in). The database subnets have no route to the internet at all —
not even via NAT.

A single NAT Gateway is shared by both AZs' private application subnets to
keep cost down. For high availability across AZ failure of the NAT itself,
add a second NAT Gateway (one per AZ) — see `docs/SECURITY.md` /
cost-considerations in the README for the trade-off.

## Why these technology choices

- **ECS Fargate over EKS/Kubernetes**: no cluster nodes to patch, no
  control plane to manage, and the requirements explicitly exclude
  Kubernetes-adjacent tooling. Fargate is the simplest way to run a
  container on AWS with production-grade scaling and health management.
- **Node.js/Express for the sample app**: minimal dependencies, fast
  startup (matters for Fargate cold starts and CI cycle time), and a
  health-check/graceful-shutdown pattern that's easy to read even if you
  don't write JavaScript day to day.
- **Terraform over CloudFormation/CDK**: cloud-agnostic skill, explicit
  state, and the most common IaC tool asked about in DevOps interviews.
- **GitHub Actions OIDC over IAM access keys**: short-lived, per-workflow-run
  credentials; nothing to rotate or leak.
- **S3 native locking (`use_lockfile`) over S3+DynamoDB**: Terraform 1.10+
  added native state locking via S3 conditional writes, removing the need
  for a separate DynamoDB table that earlier Terraform versions required.
  One less resource to provision, patch, and pay for.
- **RDS-managed master password (Secrets Manager) over a Terraform-supplied
  password**: the database password is never written to Terraform state,
  never appears in a `terraform plan` diff, and is rotated by AWS.

## Module boundaries

| Module | Owns |
|---|---|
| `vpc` | VPC, subnets, IGW, NAT, route tables, security groups |
| `rds` | DB subnet group, KMS key, RDS instance, managed secret |
| `alb` | Load balancer, target group, HTTP listener |
| `ecr` | Container image repository + lifecycle policy (staging only, shared) |
| `iam` | ECS task execution role, ECS task role, GitHub OIDC provider + deploy role |
| `ecs` | Cluster, task definition, service, autoscaling |
| `cloudwatch` | Log group, 2 dashboards, alarms, SNS topic |

`envs/staging` and `envs/prod` each call every module except `ecr` (prod
reuses staging's repository via `terraform_remote_state`) — keeping the
per-environment files thin: mostly variable values, not resource logic.

## Deployment flow (CI/CD)

1. PR opened -> tests run (no AWS access needed).
2. Merge to `main` -> tests run again -> Docker image built and pushed to
   ECR, tagged with the 12-character Git commit SHA.
3. New ECS task definition revision registered pointing at that image ->
   staging service updated -> `aws ecs wait services-stable`.
4. Smoke test against the staging ALB (`/health`, `/`).
5. **Manual approval gate** (GitHub Environment `production` with required
   reviewers) — the workflow pauses here.
6. Same image (not rebuilt) promoted to production the same way.
7. Smoke test against the production ALB.

The same immutable image that passed staging is the one deployed to
production — nothing is rebuilt between environments.

## Rollback

Rollback is a deliberate manual step (see the workflow file's inline
comment and the README's Troubleshooting section) — `aws ecs update-service
--task-definition <previous-revision-arn>`. It is not automated so that a
failing prod smoke test surfaces to a human rather than silently
flip-flopping.
