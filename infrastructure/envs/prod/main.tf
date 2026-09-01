locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  # Reused from staging instead of re-creating: a shared ECR repository
  # (images are built once and promoted staging -> prod) and the single
  # GitHub OIDC provider that is allowed to exist per AWS account.
  ecr_repository_url = data.terraform_remote_state.staging.outputs.ecr_repository_url
  oidc_provider_arn   = data.terraform_remote_state.staging.outputs.oidc_provider_arn
}

module "vpc" {
  source = "../../modules/vpc"

  project_name        = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  app_subnet_cidrs     = var.app_subnet_cidrs
  db_subnet_cidrs      = var.db_subnet_cidrs
  app_container_port   = var.app_container_port
  tags                = local.tags
}

module "rds" {
  source = "../../modules/rds"

  project_name           = var.project_name
  environment            = var.environment
  db_subnet_ids           = module.vpc.db_subnet_ids
  rds_security_group_id   = module.vpc.rds_security_group_id
  instance_class           = var.db_instance_class
  multi_az                 = var.db_multi_az
  deletion_protection      = true
  skip_final_snapshot      = false
  backup_retention_days    = 14
  tags                    = local.tags
}

module "alb" {
  source = "../../modules/alb"

  project_name            = var.project_name
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  public_subnet_ids        = module.vpc.public_subnet_ids
  alb_security_group_id    = module.vpc.alb_security_group_id
  app_container_port       = var.app_container_port
  tags                    = local.tags
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name             = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  log_retention_days        = var.log_retention_days
  ecs_cluster_name           = module.ecs.cluster_name
  ecs_service_name           = module.ecs.service_name
  alb_arn_suffix             = module.alb.alb_arn_suffix
  target_group_arn_suffix    = module.alb.target_group_arn_suffix
  rds_instance_id            = module.rds.db_instance_id
  desired_task_count         = var.desired_count
  sns_alarm_email            = var.sns_alarm_email
  tags                      = local.tags
}

module "iam" {
  source = "../../modules/iam"

  project_name          = var.project_name
  environment           = var.environment
  ecr_repository_arn    = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-app"
  db_secret_arn          = module.rds.master_user_secret_arn
  log_group_arn          = module.cloudwatch.log_group_arn
  github_org             = var.github_org
  github_repo            = var.github_repo
  create_oidc_provider   = false
  github_oidc_provider_arn = local.oidc_provider_arn
  tags                  = local.tags
}

data "aws_caller_identity" "current" {}

module "ecs" {
  source = "../../modules/ecs"

  project_name                 = var.project_name
  environment                   = var.environment
  vpc_id                        = module.vpc.vpc_id
  app_subnet_ids                 = module.vpc.app_subnet_ids
  ecs_tasks_security_group_id    = module.vpc.ecs_tasks_security_group_id
  target_group_arn               = module.alb.target_group_arn
  ecr_repository_url             = local.ecr_repository_url
  image_tag                     = var.image_tag
  app_container_port             = var.app_container_port
  task_cpu                      = var.task_cpu
  task_memory                    = var.task_memory
  desired_count                  = var.desired_count
  min_capacity                   = var.min_capacity
  max_capacity                    = var.max_capacity
  task_execution_role_arn        = module.iam.task_execution_role_arn
  task_role_arn                  = module.iam.task_role_arn
  db_address                     = module.rds.db_address
  db_port                        = module.rds.db_port
  db_name                        = module.rds.db_name
  db_username                     = module.rds.db_username
  db_secret_arn                   = module.rds.master_user_secret_arn
  log_group_name                  = module.cloudwatch.log_group_name
  tags                           = local.tags
}
