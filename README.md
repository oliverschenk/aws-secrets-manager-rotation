# AWS Secrets Manager Rotation

This repo contains the code for the Medium article [Achieving RDS password rotation with Secrets Manager](https://medium.com/@oliver.schenk/achieving-rds-password-rotation-with-secrets-manager-3444fa30c94b)

Please note that the resources created by this project are NOT free. Deploy at your own risk and destroy when no longer needed.

If you are interested in how to read secrets from Secrets Manager and perform database migrations see the article [Read Secrets Manager secrets and perform RDS database migrations using Lambda](https://medium.com/@oliver.schenk/read-secrets-manager-secrets-and-perform-rds-database-migrations-using-lambda-7bbea31938b4).

## Prerequisites

- Terraform
- AWS account with Administrator access
- aws-vault (only required if using deployment script `deploy.sh`)

## Getting Started

### Running terraform manually

This method assumes you have credentials set up appropriately.

```
terraform init
terraform apply
```

### Using the deploy script

This method assumes you have aws-vault configured.

You can configure the default region in the `deploy.sh` file.


```
./deploy.sh

DESCRIPTION:
  Script for deploying serverless lambda.

USAGE:
  deploy.sh -p credentials_profile [-r region] [-s stage] [-d destroy]

OPTIONS
  -p   the credentials profile to use (uses aws-vault)
  -r   region (default: ap-southeast-2)
  -s   the stage to deploy [dev, test, prod] (default: dev)
  -d   destroy
```

```
# to apply
./deploy.sh -p <aws_vault_profile>

# to destroy
./deploy.sh -p <aws_vault_profile> -d
```