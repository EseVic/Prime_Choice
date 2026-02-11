module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_vpn_gateway     = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Security group for EKS cluster
resource "aws_security_group" "eks_cluster" {
  name        = "eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "eks-cluster-sg"
    Environment = "dev"
  }
}

# Security group for EKS nodes
resource "aws_security_group" "eks_nodes" {
  name        = "eks-node-sg"
  description = "Security group for EKS nodes"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "eks-node-sg"
    Environment = "dev"
  }
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

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

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Node IAM Role
resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.29"

  cluster_endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  cluster_security_group_id = aws_security_group.eks_cluster.id
  node_security_group_id    = aws_security_group.eks_nodes.id

  access_entries = {
  admin = {
    principal_arn = "arn:aws:iam::980805786514:user/EseVic"

    policy_associations = {
      admin = {
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = {
          type = "cluster"
        }
      }
    }
  }
}


  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    default = {
      name = "eks-node-group"

      min_size     = 2
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.small"]

      iam_role_arn = aws_iam_role.eks_nodes.arn
      vpc_security_group_ids = [aws_security_group.eks_nodes.id]

      tags = {
        Name = "eks-node-group"
      }
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    module.vpc
  ]
}

resource "null_resource" "update_kubeconfig" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
  }

  depends_on = [module.eks]
}


# module "vpc" {
#   source = "terraform-aws-modules/vpc/aws"
#   version = "~> 5.0"

#   name = "eks-vpc"
#   cidr = "10.0.0.0/16"

#   azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
#   private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

#   enable_nat_gateway     = true
#   single_nat_gateway     = true
#   one_nat_gateway_per_az = false
#   enable_vpn_gateway     = false

#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Terraform   = "true"
#     Environment = "dev"
#   }

#   public_subnet_tags = {
#     "kubernetes.io/role/elb" = "1"
#   }

#   private_subnet_tags = {
#     "kubernetes.io/role/internal-elb" = "1"
#   }
# }

# # Security group for EKS cluster
# resource "aws_security_group" "eks_cluster" {
#   name        = "eks-cluster-sg"
#   description = "Security group for EKS cluster"
#   vpc_id      = module.vpc.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name        = "eks-cluster-sg"
#     Environment = "dev"
#   }
# }

# # Security group for EKS nodes
# resource "aws_security_group" "eks_nodes" {
#   name        = "eks-node-sg"
#   description = "Security group for EKS nodes"
#   vpc_id      = module.vpc.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name        = "eks-node-sg"
#     Environment = "dev"
#   }
# }

# # EKS Cluster IAM Role
# resource "aws_iam_role" "eks_cluster" {
#   name = "eks-cluster-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "eks.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
#   role       = aws_iam_role.eks_cluster.name
# }

# # EKS Node IAM Role
# resource "aws_iam_role" "eks_nodes" {
#   name = "eks-node-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#   role       = aws_iam_role.eks_nodes.name
# }

# resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#   role       = aws_iam_role.eks_nodes.name
# }

# resource "aws_iam_role_policy_attachment" "ec2_container_registry_readonly" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.eks_nodes.name
# }

# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 20.0"

#   cluster_name    = "my-cluster"
#   cluster_version = "1.29"

#   cluster_endpoint_public_access = true

#   vpc_id                   = module.vpc.vpc_id
#   subnet_ids               = module.vpc.private_subnets
#   control_plane_subnet_ids = module.vpc.public_subnets

#   cluster_security_group_id = aws_security_group.eks_cluster.id
#   node_security_group_id    = aws_security_group.eks_nodes.id

#   cluster_addons = {
#     coredns = {
#       most_recent = true
#     }
#     kube-proxy = {
#       most_recent = true
#     }
#     vpc-cni = {
#       most_recent = true
#     }
#   }

#   # EKS Managed Node Group(s)
#   eks_managed_node_groups = {
#     default = {
#       name = "eks-node-group"

#       min_size     = 2
#       max_size     = 3
#       desired_size = 2

#       instance_types = ["t3.small"]

#       # Use the IAM role created above
#       iam_role_arn = aws_iam_role.eks_nodes.arn

#       # Attach the security group
#       vpc_security_group_ids = [aws_security_group.eks_nodes.id]

#       tags = {
#         Name = "eks-node-group"
#       }
#     }
#   }

#   tags = {
#     Environment = "dev"
#     Terraform   = "true"
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_cluster_policy,
#     module.vpc
#   ]
# }

# # Configure kubectl access
# resource "null_resource" "update_kubeconfig" {
#   triggers = {
#     always_run = timestamp()
#   }

#   provisioner "local-exec" {
#     command = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
#   }

#   depends_on = [module.eks]
# }

# output "cluster_endpoint" {
#   description = "Endpoint for EKS control plane"
#   value       = module.eks.cluster_endpoint
# }

# output "cluster_security_group_id" {
#   description = "Security group ids attached to the cluster control plane"
#   value       = module.eks.cluster_security_group_id
# }

# output "region" {
#   description = "AWS region"
#   value       = "us-east-1"
# }

# output "cluster_name" {
#   description = "Kubernetes Cluster Name"
#   value       = module.eks.cluster_name
# }




































# ################################
# # VPC
# ################################
# module "vpc" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "~> 5.0"

#   name = "eks-vpc"
#   cidr = "10.0.0.0/16"

#   azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
#   private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

#   enable_nat_gateway = true
#   single_nat_gateway = true

#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Terraform   = "true"
#     Environment = "dev"
#   }
# }

# resource "aws_iam_role" "my_admin_role" {
#   name = "eks-admin-role"
#   assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
# }

# data "aws_iam_policy_document" "eks_assume_role_policy" {
#   statement {
#     effect = "Allow"
#     principals {
#       type        = "Service"
#       identifiers = ["eks.amazonaws.com"]
#     }
#     actions = ["sts:AssumeRole"]
#   }
# }


# ################################
# # EKS
# ################################
# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 19.0"

#   ################################
#   # Cluster
#   ################################
#   cluster_name    = "my-cluster"
#   cluster_version = "1.29"

#   vpc_id                   = module.vpc.vpc_id
#   subnet_ids               = module.vpc.private_subnets
#   control_plane_subnet_ids = module.vpc.private_subnets

#   cluster_endpoint_public_access = true


#   ################################
#   # Addons
#   ################################
#   cluster_addons = {
#     coredns = {
#       most_recent = true
#     }
#     kube-proxy = {
#       most_recent = true
#     }
#     vpc-cni = {
#       most_recent = true
#     }
#     eks-pod-identity-agent = {
#       most_recent = true
#     }
#   }

#   ################################
#   # Managed Node Groups
#   ################################
#   eks_managed_node_groups = {
#     workers = {
#       ami_type       = "AL2023_x86_64_STANDARD"
#       instance_types = ["t3.medium"]

#       min_size     = 2
#       max_size     = 2
#       desired_size = 2

#       capacity_type = "ON_DEMAND"
#     }
#   }

#   tags = {
#     Terraform   = "true"
#     Environment = "dev"
#   }
# }



























# module "vpc" {
#   source = "terraform-aws-modules/vpc/aws"

#   name = "eks-vpc"
#   cidr = "10.0.0.0/16"

#   azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
#   private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

#   enable_nat_gateway = true
#   enable_vpn_gateway = true

#   tags = {
#     Terraform = "true"
#     Environment = "dev"
#   }
# }




# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 21.0"

#   name               = "my-cluster"
#   kubernetes_version = "1.33"

#   addons = {
#     coredns                = {}
#     eks-pod-identity-agent = {
#       before_compute = true
#     }
#     kube-proxy             = {}
#     vpc-cni                = {
#       before_compute = true
#     }
#   }

#   # Optional
#   endpoint_public_access = true

#   # Optional: Adds the current caller identity as an administrator via cluster access entry
#   enable_cluster_creator_admin_permissions = true

#   vpc_id                   = module.vpc.vpc_id
#   subnet_ids               = ["subnet-abcde012", "subnet-bcde012a", "subnet-fghi345a"]
#   control_plane_subnet_ids = ["subnet-xyzde987", "subnet-slkjf456", "subnet-qeiru789"]

#   # EKS Managed Node Group(s)
#   eks_managed_node_groups = {
#     example = {
#       # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
#       ami_type       = "AL2023_x86_64_STANDARD"
#       instance_types = ["t3.small"]

#       min_size     = 2
#       max_size     = 2
#       desired_size = 2
#     }
#   }

#   tags = {
#     Environment = "dev"
#     Terraform   = "true"
#   }
# }

























# compute_config = {
#    enabled = false
#   }

# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 21.0"

#   name               = "wtf-eks"
#   kubernetes_version = "1.33"

#   # Optional
#   endpoint_public_access = true

#   # Optional: Adds the current caller identity as an administrator via cluster access entry
#   enable_cluster_creator_admin_permissions = true

#  # compute_config = {
#   #  enabled    = true
#    # node_pools = ["general-purpose"]
#  # }

#   vpc_id     = module.vpc.vpc_id
#   subnet_ids = module.vpc.subnet_ids

#   tags = {
#     Environment = "dev"
#     Terraform   = "true"
#   }
# }
