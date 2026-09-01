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

resource "aws_lb" "this" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${local.name}-alb" })
}

resource "aws_lb_target_group" "this" {
  name        = "${local.name}-tg"
  port        = var.app_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for Fargate

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 15

  tags = merge(var.tags, { Name = "${local.name}-tg" })
}

# NOTE: HTTP-only listener on port 80 to keep the project runnable without a
# purchased domain/ACM certificate. For production use, add an HTTPS
# listener on 443 with an ACM certificate and redirect 80 -> 443. See
# docs/SECURITY.md for the exact resources to add.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
