terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# ECS TASK EXECUTION ROLE
# Used by the ECS agent itself (not application code) to: pull the image
# from ECR, fetch the DB secret referenced in the task definition's
# `secrets` block, and write container logs to CloudWatch. This is
# intentionally separate from the task role below (least privilege: the
# execution role never has application-level AWS permissions).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_extra" {
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }

  statement {
    sid = "WriteLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${var.log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_execution_extra" {
  name   = "${local.name}-task-execution-extra"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_extra.json
}

# ---------------------------------------------------------------------------
# ECS TASK ROLE
# Assumed by the *application code inside the container* (via the container
# credentials endpoint). This sample app doesn't call AWS APIs itself, so
# the role is created with no inline permissions beyond assume-role — it
# exists so future application features can be granted permissions here
# without ever touching the execution role.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

# ---------------------------------------------------------------------------
# GITHUB ACTIONS OIDC — no long-lived AWS access keys.
# The trust policy is scoped to a specific GitHub org/repo and, optionally,
# branch/environment via the `sub` condition — customize var.github_org and
# var.github_repo in envs/*/terraform.tfvars.
# ---------------------------------------------------------------------------
variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "create_oidc_provider" {
  description = "Only one GitHub OIDC provider is needed per AWS account. Set true in the FIRST environment you deploy (e.g. staging), false in every subsequent one, passing its ARN via github_oidc_provider_arn instead."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "Existing OIDC provider ARN to reuse when create_oidc_provider = false."
  type        = string
  default     = ""
}

data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  # Only one OIDC provider per AWS account is needed; if it already exists
  # (e.g. created by another stack), set create_oidc_provider = false and
  # pass its ARN via github_oidc_provider_arn instead of re-creating it.
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.github_oidc_provider_arn
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub immutable repository subject claims include the owner
    # and repository IDs. Allow only this repository's main branch
    # and staging environment workflows.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:Abhilashkonda77@92944744/aws-devops-infrastructure@1351696261:ref:refs/heads/main",
        "repo:Abhilashkonda77@92944744/aws-devops-infrastructure@1351696261:environment:staging",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${local.name}-github-actions-deploy-role"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume.json
  max_session_duration = 3600
  tags                 = var.tags
}

# Deployment permissions: push to ECR, update the ECS service, and read
# logs/services needed by `aws ecs wait` during the deploy step. Scoped to
# this project's resources, not "*".
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken does not support resource-level scoping
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid = "EcsDeploy"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:ListTasks",
    ]
    resources = ["*"] # ECS describe/register actions require "*"; scoped by role trust policy instead
  }

  statement {
    sid     = "PassRolesToEcs"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.task_execution.arn,
      aws_iam_role.task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "${local.name}-github-actions-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
