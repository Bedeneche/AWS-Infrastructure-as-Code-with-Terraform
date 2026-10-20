terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.0"
    }
  }
}
provider "aws" {
  region = var.region
}
resource "aws_vpc" "tech365-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "tech365-vpc"
  }
}

# Create a subnet
resource "aws_subnet" "tech365-subnet" {
  vpc_id                  = aws_vpc.tech365-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "tech365-subnet"
  }
}

resource "aws_subnet" "tech365-subnet-a" {
  vpc_id                  = aws_vpc.tech365-vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "tech365-subnet-a"
  }
}

# internet gateway

resource "aws_internet_gateway" "tech365-igw" {
  vpc_id = aws_vpc.tech365-vpc.id

  tags = {
    Name = "tech365-igw"
  }
}

#crete security group
resource "aws_security_group" "tech365-sg" {
  name        = "tech365-sg"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.tech365-vpc.id

  tags = {
    Name = "tech365-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.tech365-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.tech365-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.tech365-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

#creating route table
resource "aws_route_table" "tech365-rt" {
  vpc_id = aws_vpc.tech365-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tech365-igw.id
  }


  tags = {
    Name = "tech365-rt"
  }
}

#associate route table with subnet and internet gateway
resource "aws_route_table_association" "tech365-subnet-rt" {
  subnet_id      = aws_subnet.tech365-subnet.id
  route_table_id = aws_route_table.tech365-rt.id
}

resource "aws_route_table_association" "tech365-subnet-a-rt" {
  subnet_id      = aws_subnet.tech365-subnet-a.id
  route_table_id = aws_route_table.tech365-rt.id
}

#create ec2 instance

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "ec2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  user_data                   = file("${path.module}/ec2-script.sh")
  subnet_id                   = aws_subnet.tech365-subnet.id
  vpc_security_group_ids      = [aws_security_group.tech365-sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  tags = {
    Name = "tech365-instance"
  }
}
output "instance_public_ip" {
  value = aws_instance.ec2.public_ip
}

resource "aws_key_pair" "tech365" {
  key_name   = "tech365-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
}

# creating volumes
resource "aws_volume_attachment" "tech365_volume" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.tech365_volume.id
  instance_id = aws_instance.ec2.id
}

resource "aws_ebs_volume" "tech365_volume" {
  availability_zone = "us-east-1b"
  size              = 5
  type              = "gp3"

  tags = {
    Name = "tech365-volume"
  }
}

resource "aws_security_group" "tech365_alb" {
  name        = "tech365-alb-sg"
  description = "Allow public HTTP traffic to the load balancer"
  vpc_id      = aws_vpc.tech365-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "tech365_asg" {
  name        = "tech365-asg-sg"
  description = "Allow HTTP from the load balancer to app instances"
  vpc_id      = aws_vpc.tech365-vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.tech365_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "tech365" {
  name               = "tech365-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tech365_alb.id]
  subnets            = [aws_subnet.tech365-subnet.id, aws_subnet.tech365-subnet-a.id]
}

resource "aws_lb_target_group" "tech365" {
  name     = "tech365-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.tech365-vpc.id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "tech365_http" {
  load_balancer_arn = aws_lb.tech365.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tech365.arn
  }
}

resource "aws_launch_template" "tech365" {
  name_prefix   = "tech365-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  user_data     = base64encode(file("${path.module}/script.sh"))

  vpc_security_group_ids = [aws_security_group.tech365_asg.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "tech365-asg-instance"
    }
  }
}

resource "aws_autoscaling_group" "tech365" {
  name                      = "tech365-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 5
  vpc_zone_identifier       = [aws_subnet.tech365-subnet.id, aws_subnet.tech365-subnet-a.id]
  target_group_arns         = [aws_lb_target_group.tech365.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.tech365.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "tech365-asg-instance"
    propagate_at_launch = true
  }
}

output "load_balancer_url" {
  value = "http://${aws_lb.tech365.dns_name}"
}
