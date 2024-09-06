terraform {
  required_providers {
      aws = {
       source  = "hashicorp/aws"
       version = "~> 4.16"
      }
   }
     required_version = ">= 1.2.0"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "${var.cidr_block}"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags = {
  Name = "My-tf-vpc"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "cluster-vpc-subnets-public" {
 vpc_id             = aws_vpc.my_vpc.id
 count              = length(var.subnets_public)
 availability_zone  = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
 cidr_block         = element(var.subnets_public, count.index)
 tags = {
     Name = "${var.name_prefix}-subnets_public-${count.index}"
  }
}

resource "aws_subnet" "cluster-vpc-subnets-private" {
 vpc_id             = aws_vpc.my_vpc.id
 count              = length(var.subnets_private)
 availability_zone  = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
 cidr_block         = element(var.subnets_private, count.index)
 tags = {
     Name = "${var.name_prefix}-subnets_private-${count.index}"
  }
}

resource "aws_internet_gateway" "my_gate_way"{
  vpc_id = aws_vpc.my_vpc.id

    tags = {
        Name = "my-terraform-igw"
    }
}


resource "aws_route_table" "terraform-public" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
       Name = "my-terraform-rt-public01"
 }
}

resource "aws_route_table" "terraform-private" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
       Name = "my-terraform-rt-private01"
 }
}
resource "aws_route" "terrform-igw-route" {
  route_table_id            = aws_route_table.terraform-public.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                =  aws_internet_gateway.my_gate_way.id
}
resource "aws_route_table_association" "terraform-public" {
  count          = length(var.subnets_public)
  subnet_id      = element(aws_subnet.cluster-vpc-subnets-public.*.id, count.index)
  route_table_id = aws_route_table.terraform-public.id
}

resource "aws_route_table_association" "terraform-private" {
  count          = length(var.subnets_private)
  subnet_id      = element(aws_subnet.cluster-vpc-subnets-private.*.id, count.index)
  route_table_id = aws_route_table.terraform-private.id
}


resource "aws_security_group" "bastion-sg" {
  name        = "T_bastion-sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description      = "all trafic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
   // ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
   // ipv6_cidr_blocks = ["::/0"]
  }
tags = {
    Name = "terraform_bastion_sg"
  }
}

resource "aws_security_group" "Private-sg" {
  name        = "T_private-sg"
  description = "private security proup "
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    security_groups  = [aws_security_group.bastion-sg.id]

  }
  dynamic "ingress" {
    for_each = [80,8080,443,9090,9000]
    iterator = port
    content {
      description = "TLS from VPC"
      from_port   = port.value
      to_port     = port.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
 egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]

  }

  tags = {
    Name = "terraform_private_sg"
  }
}

resource "aws_instance" "web" {
  ami = "ami-0a493f6d8c0886281"
  instance_type = "t2.micro"

  subnet_id  = element(aws_subnet.cluster-vpc-subnets-public.*.id, count.index)
  associate_public_ip_address  = true
  key_name = "demo-key-tf"
  count = 1
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]

  tags = {
    Name = "MY_Terrafom_Instance-bastion-${count.index}"
  }
}

resource "aws_instance" "slave" {
  ami = "ami-0d3f444bc76de0a79"
  instance_type = "t2.micro"

  subnet_id  = element(aws_subnet.cluster-vpc-subnets-public.*.id, count.index)
  associate_public_ip_address  = false
  key_name = "demo-key-tf"
  count = 2
 vpc_security_group_ids = [aws_security_group.Private-sg.id]

  tags = {
    Name = "MY_Terrafom_Instance-private-${count.index}"
  } 
}
  
