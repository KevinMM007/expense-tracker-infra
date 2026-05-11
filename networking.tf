# ---------------------------------------------------------------------------
# Networking layer: VPC, subnets, Internet Gateway, route tables.
#
# Design choices that keep the bill at ~$0:
#   - Lambda lives in the SAME private subnets as RDS, so it can reach the
#     database over private DNS without needing internet access.
#   - We deliberately DO NOT create a NAT Gateway (~$35/month minimum).
#     Lambda doesn't need outbound internet for this workload; for AWS service
#     APIs (Secrets Manager, etc.) we'll add VPC endpoints later if required.
#   - Public subnets exist but are empty for now. They're cheap (free) and
#     leave room for a future bastion host or ALB without rewriting the VPC.
# ---------------------------------------------------------------------------

# Pull the list of AZs available in the current region. We filter out AZs that
# require opt-in (Local Zones, Wavelength, etc.) so we only get standard ones.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Internet Gateway — attached to the VPC so public subnets can reach the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ---------- Public subnets ----------
# One per AZ. CIDRs derived deterministically from the VPC CIDR via cidrsubnet:
#   public[0] -> 10.0.1.0/24
#   public[1] -> 10.0.2.0/24
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(local.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Tier = "public"
  }
}

# ---------- Private subnets ----------
# One per AZ. These host the RDS instance and the Lambda function.
#   private[0] -> 10.0.11.0/24
#   private[1] -> 10.0.12.0/24
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, count.index + 11)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Tier = "private"
  }
}

# ---------- Route tables ----------

# Public RT — sends 0.0.0.0/0 to the Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private RT — no internet route on purpose (see file header).
# Intra-VPC traffic uses the implicit local route AWS adds automatically.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
