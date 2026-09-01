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

resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, { Name = "${local.name}-cluster" })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = var.task_cpu
  memory                    = var.task_memory
  execution_role_arn        = var.task_execution_role_arn
  task_role_arn              = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.app_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = tostring(var.app_container_port) },
        { name = "APP_ENV", value = var.environment },
        { name = "APP_VERSION", value = var.image_tag },
        { name = "DB_HOST", value = var.db_address },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USER", value = var.db_username },
        { name = "DB_SSL", value = "true" },
      ]

      # Password is injected at runtime by ECS directly from Secrets Manager
      # — it is never in the task definition JSON, Terraform state plaintext,
      # or application logs.
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.app_container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = merge(var.tags, { Name = "${local.name}-app-task" })
}

data "aws_region" "current" {}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-app-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.ecs_tasks_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name    = "app"
    container_port    = var.app_container_port
  }

  # Give the container time to pass its first ALB health check during
  # deploys before the ECS deployment circuit breaker considers it failed.
  health_check_grace_period_seconds = 30

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    # Image tag / desired_count are updated by CI/CD (`aws ecs update-service`
    # and a new task definition revision), not by re-running `terraform apply`
    # with a stale tag. Ignore drift on these so CI-driven deploys and
    # Terraform don't fight each other.
    ignore_changes = [task_definition, desired_count]
  }

  tags = merge(var.tags, { Name = "${local.name}-app-service" })
}

# ---------------------------------------------------------------------------
# Application Auto Scaling — scale ECS service desired count on CPU
# utilization between min_capacity and max_capacity.
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id         = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension  = "ecs:service:DesiredCount"
  service_namespace   = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id         = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension  = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace   = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
