# ==============================================================================
# ECS Cluster (EC2 Launch Type)
# ------------------------------------------------------------------------------
resource "aws_ecs_cluster" "rstudio_cluster" {
  name = "rstudio"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ==============================================================================
# ECS Node Auto Scaling Group
# ------------------------------------------------------------------------------
resource "aws_launch_template" "ecs_lt" {
  name          = "rstudio-ecs-lt"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_nodes.id]

  user_data = base64encode(templatefile("${path.module}/scripts/ecs_userdata.sh", {
    cluster_name = aws_ecs_cluster.rstudio_cluster.name
  }))

  # THIS is what applies tags to the EC2 instances
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "rstudio-ecs-node"
      Cluster     = aws_ecs_cluster.rstudio_cluster.name
      Environment = "dev"
      AmazonECSManaged      = "true"  
    }
  }

  # optional: tags on the template object itself
  tags = { Name = "rstudio-ecs-lt" }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "rstudio-ecs-asg"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier =  [data.aws_subnet.ecs-private-subnet-1.id, 
                          data.aws_subnet.ecs-private-subnet-2.id]

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  protect_from_scale_in = true
}

# ==============================================================================
# ECS Capacity Provider (1 Task per Node)
# ------------------------------------------------------------------------------
# Links the ECS cluster to the Auto Scaling Group and enables ECS-managed scaling.
# Combined with the "distinctInstance" placement constraint in the ECS Service,
# this configuration ensures each task runs on its own EC2 node.
# ==============================================================================

resource "aws_ecs_capacity_provider" "rstudio_cp" {
  name = "rstudio-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "ENABLED"

    # Enable ECS to automatically scale the ASG up/down based on task demand
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100               # ECS keeps ASG at full capacity
      minimum_scaling_step_size = 1                 # Scale by one instance at a time
      maximum_scaling_step_size = 1
      instance_warmup_period    = 60                # Seconds before instance counted as ready
    }
  }

  tags = {
    Name = "rstudio-capacity-provider"
  }
}

# ==============================================================================
# ECS Cluster Capacity Provider Association
# ------------------------------------------------------------------------------
# Associates the ECS Capacity Provider with the RStudio ECS Cluster and makes it
# the default capacity provider for all services and tasks.
# ==============================================================================

resource "aws_ecs_cluster_capacity_providers" "rstudio_assoc" {
  cluster_name       = aws_ecs_cluster.rstudio_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.rstudio_cp.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.rstudio_cp.name
    weight            = 1
  }
}

# ==============================================================================
# ECS Task Definition (EC2 Launch Type)
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "rstudio_task" {
  family                   = "rstudio-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_runtime.arn


  container_definitions = jsonencode([
    {
      name      = "rstudio"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com/rstudio:rstudio-server-rc1"
      essential = true

      environment = [
        { name = "ADMIN_SECRET", valueFrom = "admin_ad_credentials" },
        { name = "DOMAIN_FQDN", valueFrom = var.dns_zone },
        { name = "REGION", valueFrom = data.aws_region.current.id }
      ]

      portMappings = [
        { containerPort = 8787, hostPort = 8787, protocol = "tcp" }
      ]
      mountPoints = [
        { sourceVolume = "efs-root", containerPath = "/efs" },
        { sourceVolume = "efs-home", containerPath = "/home" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/rstudio"
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "rstudio"
        }
      }
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
    subnets          =  [data.aws_subnet.ecs-private-subnet-1.id, 
                         data.aws_subnet.ecs-private-subnet-2.id]
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

# ==============================================================================
# CloudWatch Log Group for ECS RStudio Task
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "rstudio" {
  name              = "/ecs/rstudio"
  retention_in_days = 7
  tags = {
    Name        = "rstudio-log-group"
    Environment = "dev"
  }
}