############################
# VPC
############################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# Remove every rule from the default security group so nothing uses it by accident
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-default-sg-unused" }
}

############################
# Internet gateway
############################
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

############################
# Subnets (one per AZ)
############################
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # public IPs are requested explicitly on the instances

  tags = {
    Name = "${local.name}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name}-private-${local.azs[count.index]}"
    Tier = "private"
  }
}

############################
# Public route table: 0.0.0.0/0 -> Internet gateway
############################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

############################
# Private route table: local routes only (no NAT in this project)
############################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
