provider "aws" {
  version = "~> 2.0"
  region  = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  available_az_names = data.aws_availability_zones.available.names
  # Ensure we don't request more AZs than available in the region
  # TODO: Validate or warn if there are less AZs than requested for a region
  az_real_count = var.az_count > length(local.available_az_names) ? length(local.available_az_names) : var.az_count
}

### Base VPC ###
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_public_block
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-VPC"
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "private_cidr" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.vpc_private_block
}

### Public Subnets and Routing ###
resource "aws_subnet" "public_subnets" {
  count = local.az_real_count
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.public_subnet_blocks[count.index]
  availability_zone = local.available_az_names[count.index]

  tags = {
    "kubernetes.io/role/elb" = 1
    Name = "${var.name_prefix}-Public-Subnet-${local.available_az_names[count.index]}"
  }
}

locals {
  #Subnet ID => Subnet AZ
  public_subnet_az_map = {for subnet in aws_subnet.public_subnets : subnet.id => subnet.availability_zone}
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name_prefix}-Internet-Gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.name_prefix}-Public-Route-Table"
  }
}

resource "aws_route_table_association" "public_route_table_associations" {
  count = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

### NATS ###
resource "aws_eip" "nat_ips" {
  count = length(aws_subnet.public_subnets)
  depends_on = [aws_internet_gateway.igw]
  vpc = true

  tags = {
    Name = "${var.name_prefix}-NAT-EIP-${aws_subnet.public_subnets[count.index].availability_zone}"
  }
}

resource "aws_nat_gateway" "nat_gateways" {
  count = length(aws_subnet.public_subnets)
  allocation_id = aws_eip.nat_ips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = {
    Name = "${var.name_prefix}-NAT-GW-${aws_subnet.public_subnets[count.index].availability_zone}"
  }
}

locals {
  # NAT GW ID => NAT GW AZ
  nat_gateway_az_map = {for nat_gateway in aws_nat_gateway.nat_gateways : nat_gateway.id => local.public_subnet_az_map[nat_gateway.subnet_id]}
}

### Private Subnets and Routing
resource "aws_subnet" "private_subnets" {
  count = local.az_real_count
  depends_on = [aws_vpc_ipv4_cidr_block_association.private_cidr]
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.private_subnet_blocks[count.index]
  availability_zone = local.available_az_names[count.index]

  tags = {
    "kubernetes.io/role/internal-elb" = 1
    Name = "${var.name_prefix}-Private-Subnet-${local.available_az_names[count.index]}"
  }
}

locals {
  # Subnet ID => Subnet AZ
  private_subnet_az_map = {for subnet in aws_subnet.private_subnets : subnet.id => subnet.availability_zone}
}

resource "aws_route_table" "private_route_tables" {
  count = length(aws_subnet.private_subnets)
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateways[count.index].id
  }

  tags = {
    # Since we only have a single default route to a NAT GW, we'll associate with the GW's AZ
    Name = "${var.name_prefix}-Private-Route-Table-NAT-${local.nat_gateway_az_map[aws_nat_gateway.nat_gateways[count.index].id]}"
  }
}

locals {
  # Route Table AZ => Route Table Id
  private_route_table_az_lookup = {for route_table in aws_route_table.private_route_tables : local.nat_gateway_az_map[tolist(route_table.route)[0].nat_gateway_id] => route_table.id}
}

resource "aws_route_table_association" "private_route_table_associations" {
  count = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = local.private_route_table_az_lookup[aws_subnet.private_subnets[count.index].availability_zone]
}