# ==============================================================================
# Application Load Balancer
# ------------------------------------------------------------------------------
resource "aws_lb" "rstudio_alb" {
  name               = "rstudio-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_service.id]
  subnets            = [data.aws_subnet.ecs-private-subnet-1, 
                        data.aws_subnet.ecs-private-subnet-2]
}

resource "aws_lb_target_group" "rstudio_tg" {
  name        = "rstudio-tg"
  port        = 8787
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.ecs-vpc.id
  target_type = "ip"

  # Enable cookie-based stickiness so users stay on same RStudio container
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 86400 # 1 day (in seconds)
  }

  health_check {
    path                = "/auth-sign-in"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb_listener" "rstudio_listener" {
  load_balancer_arn = aws_lb.rstudio_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rstudio_tg.arn
  }
}