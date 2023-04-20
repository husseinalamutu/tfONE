terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# # Create a VPC
# resource "aws_vpc" "greymatter" {
#   cidr_block = "10.0.0.0/16"
#   tags = {
#     "Name" = "greymatter"
#   }
# }

# Create an ami
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}
# Provision the security group
resource "aws_security_group" "greymatter" {
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]

  ingress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "allow ssh"
    from_port        = 22
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = []
    self             = false
    to_port          = 22
    },
    {
      cidr_blocks      = ["0.0.0.0/0"]
      description      = "allow http"
      from_port        = 80
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 80
  }]
}
resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-east-1d"

  tags = {
    Name = "Default subnet for us-east-1d"
  }
}
resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-east-1b"

  tags = {
    Name = "Default subnet for us-east-1b"
  }
}

resource "tls_private_key" "greymatter" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "greymatter" {
  key_name   = "myKey"       # Create "myKey" to AWS!!
  public_key = tls_private_key.greymatter.public_key_openssh

  provisioner "local-exec" {    # Generate "terraform-key-pair.pem" in current directory
    command = <<-EOT
      echo '${tls_private_key.greymatter.private_key_pem}' > ./'${aws_key_pair.greymatter.key_name}'.pem
      chmod 400 ./'${aws_key_pair.greymatter.key_name}'.pem
    EOT
  }
}

# Provision Nginx-EC2 Instances
resource "aws_instance" "nginx" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.greymatter.key_name
  vpc_security_group_ids = [aws_security_group.greymatter.id]
  # # storing the nginx.sh file in the EC2 instnace
  # provisioner "file" { 
  #   source      = "nginx.sh"
  #   destination = "/tmp/nginx.sh"
  # }
  # # Executing the nginx.sh file
  # provisioner "remote-exec" {
  #   inline = [
  #     "chmod +x /tmp/nginx.sh",
  #     "sudo /tmp/nginx.sh"
  #   ]
  # }
  # connection {
  #   type        = "ssh"
  #   host        = self.public_ip
  #   user        = "ubuntu"
  #   private_key = file("${aws_key_pair.greymatter.key_name}.pem")
  #   # timeout     = "4m"
  # }
  user_data = "${file("nginx.sh")}"
  tags = { 
    Name  = "NGINX"
  }
}

# Provision Apache-EC2 Instances
resource "aws_instance" "apache" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.greymatter.key_name
  vpc_security_group_ids = [aws_security_group.greymatter.id]
  # # storing the apache.sh file in the EC2 instnace
  # provisioner "file" { 
  #   source      = "apache.sh"
  #   destination = "/tmp/apache.sh"
  # }
  # # Executing the apache.sh file
  # provisioner "remote-exec" {
  #   inline = [
  #     "chmod +x /tmp/apache.sh",
  #     "sudo /tmp/apache.sh"
  #   ]
  # }
  # connection {
  # type        = "ssh"
  # host        = self.public_ip
  # user        = "ubuntu"
  # private_key = file("${aws_key_pair.greymatter.key_name}.pem")
  # # timeout     = "4m"
  # }
  user_data = "${file("apache.sh")}"
  tags = { 
    Name  = "APACHE"
  }
}

# Create a target group

resource "aws_lb_target_group" "greymatter" {
  name     = "greymatter-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id = aws_default_vpc.default.id
}

# Attach NGINX Instance to load balancer target group

resource "aws_lb_target_group_attachment" "nginx-instance" {
  target_group_arn = aws_lb_target_group.greymatter.arn
  target_id        = aws_instance.nginx.id
  port             = 80
}

# Attach APACHE Instance to load balancer target group

resource "aws_lb_target_group_attachment" "apache-instance" {
  target_group_arn = aws_lb_target_group.greymatter.arn
  target_id        = aws_instance.apache.id
  port             = 80
}

# Create Load Balancer

resource "aws_lb" "greymatter" {
  name               = "greymatter-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.greymatter.id]
  subnets = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  tags = {
    Name = "greymatterLB"
  }
}

# Create a Load Balancer Listener Resource

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.greymatter.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.greymatter.arn
  }
}

output "lb-dns-name" {
  description = "Load Balancer DNS name"
  value       = aws_lb.greymatter.dns_name
}