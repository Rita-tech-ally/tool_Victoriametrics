resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami_id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnets[0]
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [var.sg_bastion_id]
  associate_public_ip_address = true

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("${path.root}/../sakshi.pem")
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "${path.root}/../sakshi.pem"
    destination = "/home/ubuntu/sakshi.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ubuntu/sakshi.pem"
    ]
  }

  tags = {
    Name = "Bastion_Host"
  }
}

resource "aws_instance" "vminsert" {
  ami                    = var.bastion_ami_id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnets[0]
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [var.sg_ingestion_id]

  tags = {
    Name      = "vminsert"
    component = "vminsert"
    extrarole = "vmagent"
  }
}

resource "aws_instance" "vmselect" {
  ami                    = var.bastion_ami_id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnets[0]
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [var.sg_query_id]

  tags = {
    Name      = "vmselect"
    component = "vmselect"
    extrarole = "vmalert,vmagent"
  }
}

# 2. INGESTION LAUNCH TEMPLATE (vminsert + vmagent)
resource "aws_launch_template" "ingestion" {
  name_prefix   = "${var.project_name}-${var.environment}-ingest-"
  image_id      = var.ami_id_ingestion
  instance_type = "t3.micro"
  key_name      = var.ssh_key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.sg_ingestion_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.project_name}-${var.environment}-ingest"
      component = "vminsert"
      extrarole = "vmagent"
    }
  }
}

# 4. QUERY LAUNCH TEMPLATE (vmselect + vmalert)
resource "aws_launch_template" "query" {
  name_prefix   = "${var.project_name}-${var.environment}-query-"
  image_id      = var.ami_id_query
  instance_type = "t3.micro"
  key_name      = var.ssh_key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.sg_query_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.project_name}-${var.environment}-query"
      component = "vmselect"
      extrarole = "vmalert,vmagent"
    }
  }
}

# 6. STORAGE INSTANCES (Count based with exact conditional tagging)
resource "aws_instance" "storage" {
  count                  = 3
  ami                    = var.ami_id_storage
  instance_type          = "t3.micro"
  key_name               = var.ssh_key_name
  subnet_id              = var.private_subnets[count.index % length(var.private_subnets)]
  vpc_security_group_ids = [var.sg_storage_id]

  tags = {
    Name      = "vmstorage-${count.index + 1}"
    component = "vmstorage"
    extrarole = count.index == 0 ? "grafana,vmagent" : "vmagent"
  }
}