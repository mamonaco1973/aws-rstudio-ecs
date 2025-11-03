# ==============================================================================
# DATA BLOCK: AWS VPC
# ------------------------------------------------------------------------------
# Retrieves details of an existing AWS VPC using tag filters. The VPC must
# already exist in the target AWS account and region. This avoids hardcoding
# VPC IDs and allows dynamic referencing by tag.
# ==============================================================================
data "aws_vpc" "k8s-vpc" {
  # FILTER: Select VPC by tag
  filter {
    name   = "tag:Name"  # Filter by the "Name" tag
    values = ["eks-vpc"] # Match the VPC name tag value
  }
}

# ==============================================================================
# DATA BLOCK: AWS SUBNET 1
# ------------------------------------------------------------------------------
# Retrieves details for the first public subnet by its "Name" tag. Typically
# used for associating resources like EC2 instances or load balancers with
# specific subnets.
# ==============================================================================
data "aws_subnet" "k8s-subnet-1" {
  # FILTER: Select subnet by tag
  filter {
    name   = "tag:Name"       # Filter by the "Name" tag
    values = ["pub-subnet-1"] # Match the subnet tag value
  }
}

# ==============================================================================
# DATA BLOCK: AWS SUBNET 2
# ------------------------------------------------------------------------------
# Retrieves details for the second public subnet using its "Name" tag. Useful
# for multi-AZ or high-availability deployments requiring multiple subnets.
# ==============================================================================
data "aws_subnet" "k8s-subnet-2" {
  # FILTER: Select subnet by tag
  filter {
    name   = "tag:Name"       # Filter by the "Name" tag
    values = ["pub-subnet-2"] # Match the subnet tag value
  }
}

# ==============================================================================
# DATA BLOCK: AWS PRIVATE SUBNET 1
# ------------------------------------------------------------------------------
# Retrieves information about the first private subnet using its "Name" tag.
# Enables referencing private subnets dynamically without hardcoding IDs.
# ==============================================================================
data "aws_subnet" "k8s-private-subnet-1" {
  # FILTER: Select subnet by tag
  filter {
    name   = "tag:Name"        # Filter by the "Name" tag
    values = ["priv-subnet-1"] # Match the private subnet tag
  }
}

# ==============================================================================
# DATA BLOCK: AWS PRIVATE SUBNET 2
# ------------------------------------------------------------------------------
# Retrieves information about the second private subnet using its "Name" tag.
# Supports multi-AZ or HA deployments spanning private subnets.
# ==============================================================================
data "aws_subnet" "k8s-private-subnet-2" {
  # FILTER: Select subnet by tag
  filter {
    name   = "tag:Name"        # Filter by the "Name" tag
    values = ["priv-subnet-2"] # Match the private subnet tag
  }
}
