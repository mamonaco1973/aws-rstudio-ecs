# ==============================================================================
# IAM Roles
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole-rstudio"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Add SSM read access for secrets/parameters
resource "aws_iam_role_policy_attachment" "ecs_task_ssm_readonly" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role" "ecs_task_runtime" {
  name = "ecsTaskRuntimeRole-rstudio"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# ECS Instance Role (for EC2 launch type)
resource "aws_iam_role" "ecs_instance" {
  name = "ecsInstanceRole-rstudio"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_attach" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       =  aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile-rstudio"
  role = aws_iam_role.ecs_instance.name
}

data "aws_iam_policy_document" "rstudio_task_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "rstudio_task_secrets" {
  name   = "rstudio-task-secrets-policy"
  policy = data.aws_iam_policy_document.rstudio_task_secrets_policy.json
}

resource "aws_iam_role_policy_attachment" "rstudio_task_secrets_attach" {
  role       = aws_iam_role.ecs_task_runtime.name
  policy_arn = aws_iam_policy.rstudio_task_secrets.arn
}

# Allow ECS Tasks to Create and Write to CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_task_cloudwatch_logs" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}