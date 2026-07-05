# ALB External Access Security Group
resource "aws_security_group" "alb" {
  name   = "${var.project_name}-${var.environment}-alb-sg"
  vpc_id = var.vpc_id
  tags   = { Name = "${var.project_name}-${var.environment}-alb-sg" }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 81
    to_port     = 81
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Bastion Security Group (Locked down to your Laptop public IP)
resource "aws_security_group" "bastion" {
  name   = "${var.project_name}-${var.environment}-bastion-sg"
  vpc_id = var.vpc_id
  tags   = { Name = "${var.project_name}-${var.environment}-bastion-sg" }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Ingestion Nodes SG (vminsert=8480, vmagent=8429)
resource "aws_security_group" "ingestion" {
  name   = "${var.project_name}-${var.environment}-ingestion-sg"
  vpc_id = var.vpc_id
  tags   = { Name = "${var.project_name}-${var.environment}-ingestion-sg" }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id] # SSH only via Bastion
  }
  ingress {
    from_port       = 8480
    to_port         = 8480
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # Metrics intake from ALB
  }
  ingress {
    from_port   = 8480
    to_port     = 8480
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Internal vmagent write access
  }
  ingress {
    from_port   = 8429
    to_port     = 8429
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Query Nodes SG (vmselect=8481, vmalert=8880)
resource "aws_security_group" "query" {
  name   = "${var.project_name}-${var.environment}-query-sg"
  vpc_id = var.vpc_id
  tags   = { Name = "${var.project_name}-${var.environment}-query-sg" }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    from_port       = 8481
    to_port         = 8481
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # Dashboards / Queries via ALB
  }
  ingress {
    from_port   = 8481
    to_port     = 8481
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Grafana internal access to vmselect
  }
  ingress {
    from_port   = 8880
    to_port     = 8880
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    from_port   = 8429
    to_port     = 8429
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Stateful Storage Backend SG (vmstorage=8400-8401, metrics=8482, grafana=3000)
resource "aws_security_group" "storage" {
  name   = "${var.project_name}-${var.environment}-storage-sg"
  vpc_id = var.vpc_id
  tags   = { Name = "${var.project_name}-${var.environment}-storage-sg" }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    from_port   = 8400
    to_port     = 8401
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Internal node cluster distribution mesh & vmselect queries
  }
  ingress {
    from_port   = 8482
    to_port     = 8482
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Internal HTTP / metrics endpoint for scraping
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Grafana internal access
  }
  ingress {
    from_port   = 8429
    to_port     = 8429
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # vmagent access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}