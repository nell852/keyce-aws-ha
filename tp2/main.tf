###############################################################
# TP2 – Architecture HA : VPC / Subnets / IGW / NAT
# Keyce Informatique – Réseaux & Sécurité – B3
###############################################################

###############################################################
# VPC PRINCIPAL
###############################################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

###############################################################
# INTERNET GATEWAY
###############################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

###############################################################
# SUBNETS PUBLICS (2 AZ)
###############################################################
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet-${count.index + 1}"
    Project = var.project_name
    Tier    = "Public"
  }
}

###############################################################
# SUBNETS PRIVÉS (2 AZ) – pour EC2, RDS
###############################################################
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name    = "${var.project_name}-private-subnet-${count.index + 1}"
    Project = var.project_name
    Tier    = "Private"
  }
}

###############################################################
# ELASTIC IPs pour NAT GATEWAYS
###############################################################
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-nat-eip-${count.index + 1}"
    Project = var.project_name
  }
}

###############################################################
# NAT GATEWAYS (1 par AZ pour HA)
###############################################################
resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name    = "${var.project_name}-nat-${count.index + 1}"
    Project = var.project_name
  }

  depends_on = [aws_internet_gateway.igw]
}

###############################################################
# ROUTE TABLES PUBLIQUES
###############################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################
# ROUTE TABLES PRIVÉES (1 par AZ)
###############################################################
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = {
    Name    = "${var.project_name}-private-rt-${count.index + 1}"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
