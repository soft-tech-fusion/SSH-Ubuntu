
provider "aws" {
  region = "eu-west-2"
}



/* This sets up project to use S3 remote backend */

terraform {
  required_version = ">= 0.14"
  backend "s3" {
    bucket         = "techfusion-state-bucket"
    key            = "global/s3/dev/ub-ssh/terraform.tfstate"
    region         = "eu-west-2"
    /* IMPORTANT!! 
    This needs to be commented on first pass 
    */
    #############################################
    dynamodb_table = "techfusion-state-table"
    #############################################
    encrypt        = true
  }
}


/* Step 1: Create VPC */
resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "main"
  }
}

/* Step 2: Internet Gateway */
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}


/* Step 3: Create Custom Route Table */
resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main"
  }
}

/* Step 4: Create Custom Subnet */
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"
  tags = {
    Name = "Main"
  }
}

/* Step 5: Route Table Association */
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.route-table.id
}


/* Step 6: Create Security Group - Ports, 22, 80 & 443*/
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow WEB inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
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

  tags = {
    Name = "allow_web"
  }
}


/* Step 7:  Create Network Interface with an IP in the subnet */
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

/* Step 8: Assign elastic IP */
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

/* Step 9: Create UBUNTU Server */
resource "aws_instance" "web-server-instance" {
  ami               = "ami-0ff4c8fb495a5a50d"
  instance_type     = "t2.micro"
  availability_zone = "eu-west-2a"
  key_name          = "techfusion-key-pair"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
      #!/bin/bash
      sudo apt update -y
      sudo apt install apache2 -y
      sudo systemctl start apache2
      sudo bash -c 'echo Hello from TechFusion Web Server - 2021 > /var/www/html/index.html'
      EOF

}
