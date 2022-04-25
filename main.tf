data "aws_caller_identity" "current" {}

locals {
  id = "${var.stage}-${var.project_name}"
}

###############################################################################
# VPC
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.0"

  name = "${local.id}-vpc"

  # base CIDR address range
  cidr = "10.10.0.0/16"

  # Configure availability zones and subnets
  # Three subnets are created:
  # - private
  # - public
  # - database
  azs              = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets  = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnets   = ["10.10.11.0/24", "10.10.12.0/24", "10.10.13.0/24"]
  database_subnets = ["10.10.21.0/24", "10.10.22.0/24", "10.10.23.0/24"]

  # enable DNS - this is required so that we can use private DNS
  # hostnames when using a VPC Endpoint
  enable_dns_hostnames = true
  enable_dns_support   = true

  # database subnet group
  database_subnet_group_name         = "${local.id}-database-subnet-group"
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  # set Name tags so that the resources are easier
  # to identify in the console
  default_security_group_tags = {
    Name = "${local.id}-default-sg"
  }

  public_subnet_tags = {
    Name = "${local.id}-public-subnet"
  }

  public_route_table_tags = {
    Name = "${local.id}-public-route-table"
  }

  private_subnet_tags = {
    Name = "${local.id}-private-subnet"
  }

  private_route_table_tags = {
    Name = "${local.id}-private-route-table"
  }

  database_subnet_tags = {
    Name = "${local.id}-database-subnet"
  }

  database_route_table_tags = {
    Name = "${local.id}-database-route-table"
  }

  igw_tags = {
    Name = "${local.id}-internet-gateway"
  }

  vpc_tags = {
    Name = "${local.id}-vpc"
  }
}

###############################################################################
# Security groups
###############################################################################

resource "aws_security_group" "secret_rotator_lambda_sg" {
  name        = "${local.id}-rotator-lambda-sg"
  description = "Lambda Rotation Function SG"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${local.id}-rds-sg"
  description = "RDS SG"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "rds_rotator_lambda_rule" {
  type      = "ingress"
  from_port = 3306
  to_port   = 3306
  protocol  = "tcp"

  security_group_id = aws_security_group.rds_sg.id

  source_security_group_id = aws_security_group.secret_rotator_lambda_sg.id
}

resource "aws_security_group_rule" "rds_rotator_egress_rule" {

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = [module.vpc.vpc_cidr_block]

  security_group_id = aws_security_group.rds_sg.id
}

resource "aws_security_group" "secrets_manager_endpoint_sg" {
  name        = "${local.id}-vpc-endpoint-sg"
  description = "Secrets Manager VPC endpoint SG"
  vpc_id      = module.vpc.vpc_id

  ingress {
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
}

###############################################################################
# RDS cluster
###############################################################################

resource "random_password" "initial_master_password" {
  length  = 12
  special = false
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = local.id

  availability_zones     = module.vpc.azs
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  engine         = "aurora-mysql"
  engine_version = var.database_engine_version

  database_name   = var.database_name
  master_username = var.database_master_username
  master_password = random_password.initial_master_password.result

  iam_database_authentication_enabled = true

  skip_final_snapshot = true
}

resource "aws_rds_cluster_instance" "this" {
  count              = 1
  identifier         = "${local.id}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id

  db_subnet_group_name = aws_rds_cluster.this.db_subnet_group_name

  instance_class = var.database_instance_type
  engine         = aws_rds_cluster.this.engine
  engine_version = aws_rds_cluster.this.engine_version
}

###############################################################################
# Secrets Manager VPC endpoint
###############################################################################

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "3.14.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.secrets_manager_endpoint_sg.id]

  # Endpoints are used to allow a particular subnet to be connected to AWS services
  # without having to go via the internet. All traffic is routed internally to AWS.
  endpoints = {

    # The Secrets Manager endpoint allows Lambda functions to call the secrets manager
    # API for the purpose of RDS key rotation from within the private subnet where the
    # Lambda function resides.
    secrets_manager = {
      service    = "secretsmanager"
      subnet_ids = module.vpc.database_subnets
      tags       = { Name = "${local.id}-endpoint" }

      // enable private DNS to ensure the VPC endpoint is exposed
      // using the standard service Uri
      private_dns_enabled = true
    }
  }
}

###############################################################################
# Lambda rotator function and role
###############################################################################

resource "aws_lambda_function" "secret_rotator_lambda" {
  function_name = "${local.id}-rotator-lambda"

  role = aws_iam_role.secret_rotator_lambda_role.arn

  handler          = "handler.lambda_handler"
  filename         = "./function/function.zip"
  source_code_hash = filebase64sha256("./function/function.zip")

  runtime = "python3.9"
  timeout = 30

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com",
      API_CONNECT_TIMEOUT      = 2,
      API_READ_TIMEOUT         = 2,
      API_RETRIES              = 10,
      LOG_LEVEL                = "DEBUG"
    }
  }

  vpc_config {
    security_group_ids = [aws_security_group.secret_rotator_lambda_sg.id]
    subnet_ids         = module.vpc.database_subnets
  }

  depends_on = [
    aws_iam_role_policy_attachment.secret_rotator_lambda_role_policy_attachment
  ]
}

resource "aws_lambda_permission" "allow_secret_manager_call_lambda" {
  function_name  = aws_lambda_function.secret_rotator_lambda.function_name
  statement_id   = "AllowExecutionSecretManager"
  action         = "lambda:InvokeFunction"
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_iam_role" "secret_rotator_lambda_role" {
  name = "${local.id}-rotator-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "secret_rotator_lambda_policy" {
  name = "${local.id}-rotator-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ],
        Resource = aws_secretsmanager_secret.db_master_password.arn,
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetRandomPassword"
        ],
        Resource = "*"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Effect   = "Allow",
        Action   = "logs:CreateLogGroup",
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.id}-rotator-lambda:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secret_rotator_lambda_role_policy_attachment" {
  role       = aws_iam_role.secret_rotator_lambda_role.id
  policy_arn = aws_iam_policy.secret_rotator_lambda_policy.arn
}

###############################################################################
# Store secret in Secrets Manager and configure rotation
###############################################################################

resource "aws_secretsmanager_secret" "db_master_password" {
  name        = "/${var.stage}/${var.project_name}/database/secret"
  description = "RDS master database secret"
}

resource "aws_secretsmanager_secret_version" "db_master_password" {
  secret_id = aws_secretsmanager_secret.db_master_password.id
  secret_string = jsonencode(
    {
      username            = aws_rds_cluster.this.master_username
      password            = aws_rds_cluster.this.master_password
      engine              = "mysql"
      host                = aws_rds_cluster.this.endpoint
      dbClusterIdentifier = aws_rds_cluster.this.id
    }
  )
}

resource "aws_ssm_parameter" "db_secret" {
  name        = "/${var.stage}/${var.project_name}/database/secret"
  description = "The secrets manager secret ARN for RDS secret"
  type        = "String"
  value       = aws_secretsmanager_secret.db_master_password.arn
}

resource "aws_secretsmanager_secret_rotation" "db_master_password_rotation" {
  secret_id           = aws_secretsmanager_secret.db_master_password.id
  rotation_lambda_arn = aws_lambda_function.secret_rotator_lambda.arn

  rotation_rules {
    automatically_after_days = var.rotation_interval
  }
}
