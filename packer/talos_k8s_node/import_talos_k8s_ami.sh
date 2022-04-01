# !/bin/bash

# This script downloads the latest raw AWS Talos image and imports it in AWS.
# If the latest release is already imported the scripts prints the AMI ID that uses this release

S3_BUCKET_NAME=${S3_BUCKET_NAME:-"infra-cm-state"}
REGION=${REGION:-"eu-west-1"}
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Get the version of the Talos image release. 
talos_release=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/talos-systems/talos/releases/latest/ | rev | cut -d "/" -f1 | rev)
echo "Latest Talos image release is" ${talos_release}

imported_talos_releases=$(aws s3 ls s3://infra-cm-state/ami/talos/ | tr -s " " | cut -d " " -f3)
for release in $imported_talos_releases; do
    if [[ $release == $talos_release"/" ]]; then
        echo "Talos release" $talos_release "already imported to AWS"
        AMI_ID=$(aws ec2 describe-images --owners ${ACCOUNT_ID} --filters Name=name,Values=Talos_${talos_release} --query 'Images[0].ImageId' --output text)
        echo "The AMI that runs Talos release" ${talos_release} "has ID" $AMI_ID
        exit 0
    fi
done

echo "Download Talos image release" ${talos_release}
curl --progress-bar -OL https://github.com/talos-systems/talos/releases/latest/download/aws-amd64.tar.gz

echo "Unpack the archive"
tar -xf aws-amd64.tar.gz

echo "Upload the unpacked raw image to S3 bucket with name" $S3_BUCKET_NAME
aws s3 cp disk.raw s3://$S3_BUCKET_NAME/ami/talos/${talos_release}/disk.raw
aws ec2 import-snapshot \
    --region $REGION \
    --description "Talos kubernetes optimized image release ${talos_release}" \
    --disk-container "Format=raw,UserBucket={S3Bucket=$S3_BUCKET_NAME,S3Key=ami/talos/${talos_release}/disk.raw}"

echo "Import the raw image from S3 as an EC2 snapshot"
snapshot_import_task_id=$(aws ec2 import-snapshot \
    --region $REGION \
    --description "Talos kubernetes optimized image release ${talos_release}" \
    --disk-container "Format=raw,UserBucket={S3Bucket=$S3_BUCKET_NAME,S3Key=ami/talos/${talos_release}/disk.raw}" \
    --query 'ImportTaskId' --output text)

echo "Wait until the import task with ID $snapshot_import_task_id is complete and the snapshot ready to use"
while true; do
    status=$(aws ec2 describe-import-snapshot-tasks --region eu-west-1 --import-task-ids $snapshot_import_task_id --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)
    if [ $status == "completed" ]; then
        echo "Snapshot successfully imported."
        break
    else
        echo "Still waiting..."
        sleep 5
    fi
done

snapshot_id=$(aws ec2 describe-import-snapshot-tasks --region eu-west-1 --import-task-ids $snapshot_import_task_id --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)

echo "Register new AMI with the imported snapshot"
AMI_ID=$(aws ec2 register-image \
    --region $REGION \
    --block-device-mappings "DeviceName=/dev/xvda,VirtualName=talos,Ebs={DeleteOnTermination=true,SnapshotId=$snapshot_id,VolumeSize=4,VolumeType=gp2}" \
    --root-device-name /dev/xvda \
    --virtualization-type hvm \
    --architecture x86_64 \
    --ena-support \
    --name Talos_${talos_release} \
    --query 'ImageId' --output text)

echo "The AMI ID that runs Talos release" ${talos_release} "is" $AMI_ID