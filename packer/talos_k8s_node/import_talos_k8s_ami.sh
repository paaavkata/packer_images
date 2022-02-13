# !/bin/bash

# This script downloads the latest raw AWS Talos image and imports it in AWS.

S3_BUCKET_NAME=${S3_BUCKET_NAME:-"infra-cm-state"}
REGION=${REGION:-"eu-west-1"}

# Get the version of the Talos image release. 
talos_release=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/talos-systems/talos/releases/latest/ | rev | cut -d "/" -f1 | rev)
echo "Latest Talos image release is" ${talos_release}

echo "Download Talos image release" ${talos_release}
curl --progress-bar -OL https://github.com/talos-systems/talos/releases/latest/download/aws-amd64.tar.gz

echo "Unpack the archive"
tar -xf aws-amd64.tar.gz

echo "Upload the unpacked raw image to S3 bucket with name" $S3_BUCKET_NAME
aws s3 cp disk.raw s3://$S3_BUCKET_NAME/ami/talos/${talos_release}/disk.raw

echo "Import the raw image from S3 as a EC2 snapshot"
aws ec2 import-snapshot \
    --region $REGION \
    --description "Talos kubernetes optimized image" \
    --disk-container "Format=raw,UserBucket={S3Bucket=$S3_BUCKET_NAME,S3Key=ami/talos/${talos_release}/disk.raw}" \
    --tag-specifications "Provider=Talos,Version=${talos_release},Purpose=K8S-optimized"