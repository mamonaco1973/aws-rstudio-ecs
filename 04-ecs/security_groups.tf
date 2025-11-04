# ==============================================================================
# Security Groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_nodes" {
  name        = "ecs-nodes-sg"
  description = "ECS Node Security Group"
  vpc_id      = data.aws_vpc.ecs-vpc.id

  ingress {
    description = "Allow ECS tasks and ALB"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_service" {
  name        = "ecs-service-sg"
  description = "ECS Service Security Group"
  vpc_id      = data.aws_vpc.ecs-vpc.id

  ingress {
    description     = "Allow ALB access"
    from_port       = 8787
    to_port         = 8787
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb_service" {
  name        = "alb-service-sg"
  description = "ALB Service Security Group"
  vpc_id      = data.aws_vpc.ecs-vpc.id

  ingress {
    description     = "Allow HTTP access"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
