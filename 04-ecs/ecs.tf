# ==============================================================================
# ECS Cluster (EC2 Launch Type)
# ------------------------------------------------------------------------------
resource "aws_ecs_cluster" "rstudio_cluster" {
  name = "rstudio-ec2-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ==============================================================================
# ECS Node Auto Scaling Group
# ------------------------------------------------------------------------------
resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "rstudio-ecs-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_nodes.id]

  user_data = base64encode(templatefile("${path.module}/scripts/ecs_userdata.sh", {
    cluster_name = aws_ecs_cluster.rstudio_cluster.name
  }))
}

resource "aws_autoscaling_group" "ecs_asg" {
  name_prefix         = "rstudio-ecs-asg-"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = data.aws_subnets.private.ids

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}

# Capacity Provider
resource "aws_ecs_capacity_provider" "rstudio_cp" {
  name = "rstudio-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "ENABLED"
  }
}

resource "aws_ecs_cluster_capacity_providers" "rstudio_assoc" {
  cluster_name       = aws_ecs_cluster.rstudio_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.rstudio_cp.name]
}

# ==============================================================================
# ECS Task Definition (EC2 Launch Type)
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "rstudio_task" {
  family                   = "rstudio-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "1024"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_runtime.arn


  container_definitions = jsonencode([
    {
      name      = "rstudio"
      image     = "${aws_caller_identity.current.account_id}.dkr.ecr.${aws_region.current.name}.amazonaws.com/rstudio:rstudio-server-rc1"
      essential = true

      secrets = [
        { name = "ADMIN_SECRET", valueFrom = "admin_ad_credentials" },
        { name = "DOMAIN_FQDN", valueFrom = var.dns_zone },
        { name = "REGION", valueFrom = aws_region.current.name }
      ]

      portMappings = [
        { containerPort = 8787, hostPort = 0 }
      ]
      mountPoints = [
        { sourceVolume = "efs-root", containerPath = "/efs" },
        { sourceVolume = "efs-home", containerPath = "/home" }
      ]
    }
  ])

  volume {
    name = "efs-root"
    efs_volume_configuration {
      file_system_id     = data.aws_efs_file_system.efs.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  volume {
    name = "efs-home"
    efs_volume_configuration {
      file_system_id     = data.aws_efs_file_system.efs.id
      root_directory     = "/home"
      transit_encryption = "ENABLED"
    }
  }
}

# ==============================================================================
# ECS Service (EC2)
# ------------------------------------------------------------------------------
resource "aws_ecs_service" "rstudio_service" {
  name            = "rstudio-service"
  cluster         = aws_ecs_cluster.rstudio_cluster.id
  task_definition = aws_ecs_task_definition.rstudio_task.arn
  desired_count   = 2
  launch_type     = "EC2"

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rstudio_tg.arn
    container_name   = "rstudio"
    container_port   = 8787
  }

  depends_on = [aws_lb_listener.rstudio_listener]
}
