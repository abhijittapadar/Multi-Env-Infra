terraform {
  required_version = "~>1.12"
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~>6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
    region = var.region
  
}

resource "aws_vpc" "public" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    name = "My-Public-VPC"
  }
}

resource "aws_subnet" "public-subnet" {
    vpc_id = aws_vpc.public.id
    cidr_block = "10.0.1.0/24"
    availability_zone = var.availability_zone[0]

    tags = {
      name = "My-Public-Subnet1"
    }
}

resource "aws_subnet" "public-subnet1" {
    vpc_id = aws_vpc.public.id
    cidr_block = "10.0.2.0/24"
    availability_zone = var.availability_zone[1]

    tags = {
      name = "My-Public-Subnet2"
    }
}
resource "aws_internet_gateway" "My-IGW" {
  vpc_id = aws_vpc.public.id

  tags = {
    name = "My-IGW-1"
  }
}

resource "aws_route_table" "Public-Route-table" {
  vpc_id = aws_vpc.public.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.My-IGW.id
  }

  tags = {
    name = "Public-Route-table-1"
  }
}

resource "aws_route_table_association" "one" {
  subnet_id = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.Public-Route-table.id
}

resource "aws_route_table_association" "two" {
  subnet_id = aws_subnet.public-subnet1.id
  route_table_id = aws_route_table.Public-Route-table.id
}

module "security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name        = "Web-App-SG"
  description = "Security group for user-service with custom ports open"
  depends_on = [ aws_vpc.public ]
  vpc_id      = aws_vpc.public.id

  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["http-80-tcp"]
  egress_rules = ["all-all"]

  tags = {
    name = "My-Public-App-SG"
  }
}

data "aws_ami" "amzlinux2" {
  most_recent = true
  owners = [ "amazon" ]
  filter {
    name = "name"
    values = [ "amzn2-ami-hvm-*-gp2" ]
  }
  filter {
    name = "root-device-type"
    values = [ "ebs" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
}

resource "aws_instance" "Web-App" {
  depends_on = [ aws_vpc.public, module.security-group ]
  ami = data.aws_ami.amzlinux2.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public-subnet.id
  vpc_security_group_ids = [module.security-group.security_group_id]
  associate_public_ip_address = true
  user_data = file("${path.module}/app1-install.sh")


  tags = {
    name = "My-Web-APP"
  }
}




resource "aws_lb" "test" {
  depends_on = [ aws_vpc.public, module.security-group ]
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security-group.security_group_id]
  subnets            = [aws_subnet.public-subnet.id, aws_subnet.public-subnet1.id]


  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "front_end" {
  depends_on = [ aws_lb.test, aws_lb_target_group.test ]
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"
  

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}

resource "aws_lb_target_group" "test" {
  depends_on = [ aws_vpc.public ]
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.public.id
}

resource "aws_lb_target_group_attachment" "test" {
  depends_on = [ aws_lb_target_group.test, aws_instance.Web-App ]
  target_group_arn = aws_lb_target_group.test.arn
  target_id        = aws_instance.Web-App.id
  port             = 80
}

output "alb_arn" {
  value = aws_lb.test.dns_name

}
