#!/usr/bin/env bash
# =============================================================================
# ecr-setup.sh
# Creates the ECR repository and sets a lifecycle policy to keep only the
# last 10 tagged images (avoids unbounded storage costs).
#
# Run from any machine/role that has ecr:CreateRepository permission.
# =============================================================================
set -euo pipefail

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
REGION="${REGION:-ap-south-1}"
ECR_REPO_NAME="${ECR_REPO_NAME:-eks-cicd}"

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "ERROR: set AWS_ACCOUNT_ID environment variable first."
    exit 1
fi

echo "=== Creating ECR repository: ${ECR_REPO_NAME} in ${REGION} ==="
aws ecr create-repository \
    --repository-name "${ECR_REPO_NAME}" \
    --region          "${REGION}" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE \
    2>/dev/null || echo "Repository already exists — skipping creation."

echo "=== Applying lifecycle policy ==="
aws ecr put-lifecycle-policy \
    --repository-name "${ECR_REPO_NAME}" \
    --region          "${REGION}" \
    --lifecycle-policy-text '{
        "rules": [
            {
                "rulePriority": 1,
                "description": "Keep last 10 tagged images",
                "selection": {
                    "tagStatus": "tagged",
                    "tagPrefixList": [""],
                    "countType": "imageCountMoreThan",
                    "countNumber": 10
                },
                "action": { "type": "expire" }
            },
            {
                "rulePriority": 2,
                "description": "Remove untagged images after 1 day",
                "selection": {
                    "tagStatus": "untagged",
                    "countType": "sinceImagePushed",
                    "countUnit": "days",
                    "countNumber": 1
                },
                "action": { "type": "expire" }
            }
        ]
    }'

echo ""
echo "ECR URI: ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"
echo "Done."
