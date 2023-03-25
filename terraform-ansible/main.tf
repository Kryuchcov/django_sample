# Terraform settings
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.23.0"
    }
  }
  required_version = "~> 1.3.4"
}

# cloud provider settings
provider "aws" {
  region     = "AQUI VA TU ZONA DE DIPONIBILIDAD"
  access_key = "AQUI VA TU USUARIO"
  secret_key = "AQUI VA TU CONTRASEÑA"
}

################################################################################################
# RESOURCES #
################################################################################################
# create a key pem to get inside instacne
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2_key"
  public_key = tls_private_key.ec2_key.public_key_openssh

  provisioner "local-exec" {
    command = <<-EOT
      if [ $( ls | grep ec2_key.pem | wc -l ) -gt 0 ]
      then
        echo chmod 777 ec2_key.pem && rm ec2_key.pem
      fi
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "${tls_private_key.ec2_key.private_key_pem}" > ec2_key.pem
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
      chmod 400 ec2_key.pem
    EOT
  }
}

######################## DJANGO EC2 ########################
resource "aws_instance" "django_instance" {
  ami                    = "ami-085284d24fe829cd0"
  instance_type          = "t2.micro"
  key_name               = "ec2_key"
  vpc_security_group_ids = [aws_security_group.django_security_group.id]

  tags = {
    Name = "django-instance"
  }
}

resource "null_resource" "django_config" {

  provisioner "remote-exec" {
    inline = ["echo 'Wait unitl ssh is ready'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ec2_key.private_key_pem
      host        = aws_instance.django_instance.public_ip
    }
  }

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ubuntu@${aws_instance.django_instance.public_ip}, --private-key ec2_key.pem django.yml -e 'public_ip=${aws_instance.django_instance.public_ip}' "
  }
}

######################## DJANGO SG ########################
resource "aws_security_group" "django_security_group" {
  name        = "django-security-group"
  description = "Security group to django, also allow config by ssh"

  ingress {
    description = "ssh config"
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "django port"
    from_port   = "8000"
    to_port     = "8000"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "django security group"
  }
}