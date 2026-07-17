resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    "Name" = "${var.name_prefix}-vpc"
  }

}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  for_each                = var.public_subnets
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true
  tags = {
    "Name"                                      = "${var.name_prefix}-public-${each.key}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  for_each          = var.private_subnets
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    "Name"                                      = "${var.name_prefix}-private-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}


resource "aws_nat_gateway" "main" {
  vpc_id            = aws_vpc.main.id
  availability_mode = "regional"
  depends_on        = [aws_internet_gateway.main]
  tags = {
    "Name" = "${var.name_prefix}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    "Name" = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    "Name" = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private.id
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
}

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags = {
    "Name" = "${var.name_prefix}-vpce-s3"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    "Name" = "${var.name_prefix}-default-sg-locked"
  }
}


resource "aws_security_group" "vpce" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "${var.name_prefix}-vpce-sg"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(["ecr.api", "ecr.dkr", "logs"])

  vpc_id              = aws_vpc.main.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    "Name" = "${var.name_prefix}-vpce-${each.key}"
  }
}

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = var.flow_log_retention_days
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  name_prefix        = "${var.name_prefix}-flowlog-"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
}

data "aws_iam_policy_document" "flow_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStream",
    ]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  name_prefix = "${var.name_prefix}-flowlog-"
  role        = aws_iam_role.flow.id
  policy      = data.aws_iam_policy_document.flow_permissions.json
}


resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow.arn
  log_destination = aws_cloudwatch_log_group.flow.arn
  tags = {
    "Name" = "${var.name_prefix}-flow-log"
  }
}