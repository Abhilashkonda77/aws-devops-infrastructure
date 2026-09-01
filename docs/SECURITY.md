# Security

This document lists the security decisions baked into the project and what
you'd add for a stricter production posture.

## Applied in this project

| Control | How |
|---|---|
| RDS not publicly accessible | `publicly_accessible = false`, no route from DB subnets to IGW/NAT |
| ECS tasks in private subnets | `assign_public_ip = false`, tasks run in app subnets only |
| ALB is the only public entry point | Only the ALB security group allows `0.0.0.0/0` inbound |
| Security groups reference security groups | ECS SG allows ALB SG by ID; RDS SG allows ECS SG by ID — no raw CIDR ranges between tiers |
| Least-privilege IAM | Task execution role and task role are separate; GitHub Actions deploy role is scoped to this project's ECR repo ARN and requires `iam:PassRole` only for the two ECS roles, conditioned on `iam:PassedToService = ecs-tasks.amazonaws.com` |
| No credentials in Git | `.gitignore` excludes `*.tfvars`, `.env`; `.example` files provided instead |
| No DB passwords in Terraform | `manage_master_user_password = true` — RDS generates and stores the password in Secrets Manager; Terraform never sees the plaintext |
| Terraform state encrypted | S3 bucket uses a customer-managed KMS key (bootstrap stack); `encrypt = true` in every backend config |
| RDS encryption enabled | `storage_encrypted = true` with a dedicated KMS key |
| GitHub OIDC, no long-lived keys | `aws_iam_openid_connect_provider` + `sts:AssumeRoleWithWebIdentity`, trust policy scoped to `repo:<org>/<repo>:*` |
| Minimal inbound ports | ALB: 80 only. ECS: app port from ALB SG only. RDS: 5432 from ECS SG only |
| Non-root container | Dockerfile creates and switches to `appuser` (UID 1001) before `CMD` |
| ECR image scanning | `scan_on_push = true` on the repository |
| Immutable image tags | `image_tag_mutability = "IMMUTABLE"` — a given SHA tag can never be overwritten |

## Deliberately out of scope (documented trade-offs)

These are common next steps for a stricter posture, intentionally left out
to keep the project runnable without extra prerequisites (a domain name,
an ACM certificate, a WAF budget, etc.):

- **HTTPS on the ALB.** The listener is HTTP-only on port 80 so the
  project doesn't require a purchased domain + ACM certificate to run
  end-to-end. To add HTTPS: request/validate an ACM certificate, add an
  `aws_lb_listener` on 443 referencing it, and change the existing 80
  listener's default action to a redirect to 443.
- **AWS WAF in front of the ALB.** Add `aws_wafv2_web_acl` and associate it
  with the ALB via `aws_wafv2_web_acl_association` for L7 protection
  (rate limiting, managed rule groups, etc.).
- **VPC Flow Logs.** Not enabled by default (extra CloudWatch Logs cost).
  Add `aws_flow_log` on the VPC if you need network-level audit trails.
- **Secrets Manager rotation schedule.** RDS-managed passwords aren't
  automatically rotated on a schedule by default; configure
  `aws_secretsmanager_secret_rotation` if you need periodic rotation.
- **Branch-scoped OIDC trust.** The GitHub OIDC trust policy currently
  allows any ref in the repo (`repo:org/repo:*`). Tighten to
  `repo:org/repo:ref:refs/heads/main` if only `main` should ever be able
  to assume the deploy role.
- **GuardDuty / Security Hub / Config.** Account-level detective controls,
  intentionally left to the account owner rather than provisioned per
  project.

## Secrets handling summary

| Secret | Where it lives | Who can read it |
|---|---|---|
| RDS master password | Secrets Manager (auto-created by RDS) | ECS task execution role only, scoped by ARN |
| GitHub -> AWS auth | Not a secret — short-lived OIDC token exchanged for temporary STS credentials per workflow run | N/A |
| Terraform state (may contain resource metadata) | S3, SSE-KMS encrypted, versioned, public access blocked | Whoever has `s3:GetObject` on that bucket/key |

Never commit `terraform.tfvars`, `.env`, or any file containing real
account IDs, bucket names with account IDs in them, or emails you don't
want public — use the provided `.example` files as templates.
