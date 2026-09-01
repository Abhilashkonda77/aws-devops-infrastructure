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

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = merge(var.tags, { Name = "${local.name}-db-subnet-group" })
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for ${local.name} RDS encryption at rest"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

# ---------------------------------------------------------------------------
# Database credentials via RDS-managed master password in Secrets Manager.
# No password is ever written to Terraform state or source control:
# `manage_master_user_password = true` tells RDS to generate the password
# and store it in a Secrets Manager secret that Terraform never reads.
# The ECS task references this same secret ARN at container-start time.
# ---------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  storage_type           = "gp3"
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.db_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name}-postgres-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(var.tags, { Name = "${local.name}-postgres" })

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}
