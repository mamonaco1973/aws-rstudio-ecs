# # ==========================================================================================
# # Standalone PostgreSQL RDS Instance (Non-Aurora)
# # ------------------------------------------------------------------------------------------
# # Purpose:
# #   - Deploys a single-instance Amazon RDS PostgreSQL 15.x database
# #   - Intended for DEV/TEST workloads with Multi-AZ support
# #   - Stores credentials securely in AWS Secrets Manager
# # ==========================================================================================

# resource "aws_db_instance" "postgres_rds" {

#   # Identification -----------------------------------------------------------
#   identifier     = "plural-instance" # Unique name for this RDS instance
#   engine         = "postgres"        # Standard PostgreSQL engine
#   engine_version = "15.12"           # AWS-supported engine version
#   instance_class = "db.t4g.micro"    # Smallest burstable instance type
#   db_name        = "postgres"        # Default database name

#   # Storage configuration ----------------------------------------------------
#   allocated_storage = 20    # Minimum required disk size (GB)
#   storage_type      = "gp3" # General-purpose SSD, cost-efficient

#   # Credentials --------------------------------------------------------------
#   username = "postgres" # Master DB username
#   password = random_password.postgres_password.result

#   # Networking ---------------------------------------------------------------
#   db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
#   vpc_security_group_ids = [aws_security_group.rds_sg.id]
#   publicly_accessible    = true # Allow public connection (DEV only)
#   multi_az               = true # Create standby in another AZ

#   # Backups and monitoring ---------------------------------------------------
#   backup_retention_period      = 5             # Retain backups for 5 days
#   backup_window                = "07:00-09:00" # Backup window (UTC)
#   performance_insights_enabled = true          # Enable performance monitoring

#   # Deletion behavior --------------------------------------------------------
#   skip_final_snapshot = true # Skip snapshot (OK for DEV use)

#   # Tags --------------------------------------------------------------------
#   tags = {
#     Name = "Plural Postgres RDS Instance"
#   }
# }

# # ==========================================================================================
# # RDS Subnet Group
# # ------------------------------------------------------------------------------------------
# # Defines the placement of RDS network interfaces across subnets.
# # Must include subnets in at least two AZs for Multi-AZ deployments.
# # ==========================================================================================

# resource "aws_db_subnet_group" "rds_subnet_group" {
#   name = "rds-subnet-group"

#   subnet_ids = [
#     aws_subnet.pub-subnet-1.id, # Public Subnet (AZ-A)
#     aws_subnet.pub-subnet-2.id  # Public Subnet (AZ-B)
#   ]

#   tags = {
#     Name = "RDS Subnet Group"
#   }
# }

# # ==========================================================================================
# # Security Group: PostgreSQL (TCP/5432)
# # ------------------------------------------------------------------------------------------
# # Controls inbound and outbound network access for the RDS instance.
# # Ingress allows PostgreSQL traffic; egress is fully open.
# # ==========================================================================================

# resource "aws_security_group" "rds_sg" {
#   name        = "rds-sg"
#   description = "Allow PostgreSQL access and open outbound traffic"
#   vpc_id      = aws_vpc.eks-vpc.id

#   # Ingress: Allow PostgreSQL (TCP/5432) from anywhere -----------------------
#   ingress {
#     from_port   = 5432
#     to_port     = 5432
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"] # ⚠️ Open to all — use cautiously in DEV only
#   }

#   # Egress: Allow all outbound traffic --------------------------------------
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"          # -1 means all protocols
#     cidr_blocks = ["0.0.0.0/0"] # Unrestricted outbound
#   }

#   tags = {
#     Name = "rds-sg"
#   }
# }

# # ==========================================================================================
# # Random Password Generator
# # ------------------------------------------------------------------------------------------
# # Produces a secure 24-character alphanumeric password for the DB master user.
# # Avoids hard-coding secrets in Terraform code or state.
# # ==========================================================================================

# resource "random_password" "postgres_password" {
#   length  = 24
#   special = false
# }

# # ==========================================================================================
# # Secrets Manager: PostgreSQL Credentials
# # ------------------------------------------------------------------------------------------
# # Stores PostgreSQL username, password, and connection details as JSON
# # in AWS Secrets Manager for secure application access.
# # ==========================================================================================

# # Secret definition ---------------------------------------------------------
# resource "aws_secretsmanager_secret" "postgres_credentials" {
#   name                    = "postgres-credentials"
#   recovery_window_in_days = 0 # Allow immediate deletion
# }

# # Secret version with credentials ------------------------------------------
# resource "aws_secretsmanager_secret_version" "postgres_credentials_version" {
#   secret_id = aws_secretsmanager_secret.postgres_credentials.id

#   secret_string = jsonencode({
#     user     = "postgres"
#     password = random_password.postgres_password.result
#     endpoint = split(":", aws_db_instance.postgres_rds.endpoint)[0]
#     uri      = "postgresql://postgres:${random_password.postgres_password.result}@${split(":", aws_db_instance.postgres_rds.endpoint)[0]}:5432/postgres"
#   })

# }
