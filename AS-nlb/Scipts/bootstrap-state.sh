#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap-state.sh - One-time creation of the S3 bucket that stores Terraform state.
# Usage: ./scripts/bootstrap-state.sh [region] [bucket-name]
# Writes backend.hcl (bucket + region) used by: terraform init -backend-config=backend.hcl
# Requires: AWS CLI configured with credentials allowed to create S3 buckets.
# -----------------------------------------------------------------------------
set -euo pipefail

REGION="${1:-ap-south-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${2:-tfstate-${ACCOUNT_ID}-${REGION}}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Bucket ${BUCKET} already exists - reusing it."
else
  echo "Creating bucket ${BUCKET} in ${REGION}..."
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

# Versioning lets you recover from a corrupted or deleted state file.
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Encrypt state at rest.
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# State can contain sensitive values: block every form of public access.
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

cat > backend.hcl <<EOF
bucket = "${BUCKET}"
region = "${REGION}"
EOF

echo "Done. Next: terraform init -backend-config=backend.hcl"
