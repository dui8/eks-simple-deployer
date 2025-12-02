variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

resource "aws_security_group" "eks_nodes_sg" {
  name        = "dui-eks-nodes-sg"
  description = "Security group for EKS nodes"
  vpc_id      = aws_vpc.vpc.id

  # 80 포트 인바운드 허용
  ingress {
    description = "Allow 80 from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 노드 간 통신 허용
  ingress {
    description = "Allow all traffic from nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # 모든 아웃바운드 허용
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dui-eks-nodes-sg"
  }
}

resource "aws_iam_role" "dui_eks_role" {
  name = var.cluster_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.dui_eks_role.name
}

resource "aws_eks_cluster" "dui_eks_cluster" {
  name     = "dui-eks"
  version  = "1.30"
  role_arn = aws_iam_role.dui_eks_role.arn

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_nodes_sg.id]

    subnet_ids = [
      aws_subnet.private_subnets[0].id,
      aws_subnet.private_subnets[1].id
    ]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_attach]
}

resource "aws_iam_role" "nodes_role" {
  name = "dui-eks-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nodes_worker_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes_role.name
}

resource "aws_iam_role_policy_attachment" "nodes_cni_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes_role.name
}

resource "aws_iam_role_policy_attachment" "nodes_ecr_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes_role.name
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.dui_eks_cluster.name
  version         = "1.30"
  node_group_name = "node_group"
  node_role_arn   = aws_iam_role.nodes_role.arn

  subnet_ids = [
    aws_subnet.private_subnets[0].id,
    aws_subnet.private_subnets[1].id
  ]

  remote_access {
    ec2_ssh_key               = var.key_name
    source_security_group_ids = [aws_security_group.eks_nodes_sg.id]
  }

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 0
  }

  update_config {
    max_unavailable = 2
  }

  labels = {
    role = "node_group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_cni_attach,
    aws_iam_role_policy_attachment.nodes_ecr_attach,
    aws_iam_role_policy_attachment.nodes_worker_attach
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}