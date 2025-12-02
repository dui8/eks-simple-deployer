data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]  # ← 이 줄 추가

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "bastion" {
    ami           = data.aws_ami.amazon-linux-2.id
    instance_type = "t3.small"
    subnet_id = aws_subnet.public_subnets[0].id
    vpc_security_group_ids = [ aws_security_group.allow_bastion_ssh.id ]
    iam_instance_profile = aws_iam_instance_profile.admin.name
    associate_public_ip_address = true
    key_name = "test"

    tags = {
        Name = "dui-bastion"
    }
}

resource "aws_security_group" "allow_bastion_ssh" {
    vpc_id = aws_vpc.vpc.id
    name = "bastion-sg"
    description = "made by Dui"
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port        = 0
        to_port          = 0
        protocol         = "-1"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
}

resource "aws_iam_role" "admin" {
  name = "AdminRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "admin" {
  name = "AdminRole"
  role = aws_iam_role.admin.name
}