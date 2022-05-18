#!/bin/bash
set -e

export NAME='my-project'

DEPLOY_ACTION='apply'
DESTROY_ACTION='destroy'

DEFAULT_REGION='ap-southeast-2'
DEFAULT_STAGE='dev'

AWS_VAULT_PREFIX=''

REGION=$DEFAULT_REGION
STAGE=$DEFAULT_STAGE
ACTION=$DEPLOY_ACTION

function usage {
    echo "DESCRIPTION:"
    echo "  Script for deploying serverless lambda."
    echo ""
    echo "USAGE:"
    echo "  deploy.sh [-p credentials_profile] [-r region] [-s stage] [-d destroy]"
    echo ""
    echo "OPTIONS"
    echo "  -p   the credentials profile to use (uses aws-vault)"
    echo "  -r   region (default: ap-southeast-2)"
    echo "  -s   the stage to deploy [dev, test, prod] (default: dev)"
    echo "  -d   destroy"
}

function aws_exec {
    ${AWS_VAULT_PREFIX}$1
}

while getopts "p:r:s:d" option; do
    case ${option} in
        p ) AWS_VAULT_PROFILE=$OPTARG;;
        r ) REGION=$OPTARG;;
        s ) STAGE=$OPTARG;;
        d ) ACTION=$DESTROY_ACTION;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            usage
            exit 1
            ;;
    esac
done

if [[ -n "${VALIDATION_ERROR}" ]]; then
    usage
    exit 1
fi

if [[ -n "${AWS_VAULT_PROFILE}" ]]; then
    AWS_VAULT_PREFIX="aws-vault exec ${AWS_VAULT_PROFILE} -- "
fi

echo "=== Using the following parameters ==="
echo "Region: ${REGION}"
echo "Stage: ${STAGE}"
echo "Action: ${ACTION}"

echo ""
echo "=== Applying action: ${ACTION} ==="
aws_exec "terraform ${ACTION} --var aws_region=${REGION}"

if [[ "${ACTION}" = "${DESTROY_ACTION}" ]]; then

  echo ""
  echo "=== Forcing deletion of secret ==="
  aws_exec "aws secretsmanager delete-secret --force-delete-without-recovery --secret-id /dev/my-project/database/secret"

fi

echo ""
echo "Completed."