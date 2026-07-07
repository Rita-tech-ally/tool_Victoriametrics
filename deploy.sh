#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-apply}"

if [ "$ACTION" = "destroy" ]; then
    echo "=== Action: Destroying VictoriaMetrics HA Infrastructure ==="

    echo "=== Step 1: Running Terraform Destroy ==="
    cd terraform
    terraform destroy -auto-approve
    cd ..

    echo "=== Step 2: Cleaning up baked AMIs and associated snapshots from AWS ==="
    # Find all AMI IDs starting with vminsert-baked- or vmselect-baked-
    for ami_id in $(aws ec2 describe-images --owners self --filters "Name=name,Values=vminsert-baked-*,vmselect-baked-*" --query "Images[].ImageId" --output text); do
        if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
            echo "Deregistering AMI: $ami_id"
            snapshot_ids=$(aws ec2 describe-images --image-ids "$ami_id" --query "Images[].BlockDeviceMappings[].Ebs.SnapshotId" --output text)
            aws ec2 deregister-image --image-id "$ami_id"
            for snap in $snapshot_ids; do
                if [ "$snap" != "None" ] && [ -n "$snap" ]; then
                    echo "Deleting snapshot: $snap"
                    aws ec2 delete-snapshot --snapshot-id "$snap"
                fi
            done
        fi
    done

    echo "=== Teardown Completed Successfully! ==="
    exit 0
fi

# Default Action: Apply / Deploy
echo "=== Action: Deploying VictoriaMetrics HA Infrastructure ==="

# 1. Run first-stage Terraform Apply (standalone nodes deployed, ASGs set to 0)
echo "=== Step 1: Deploying standalone infrastructure (ASGs scale = 0) ==="
cd terraform
terraform apply -auto-approve -lock=false \
  -var="ingestion_asg_desired=0" \
  -var="ingestion_asg_min=0" \
  -var="query_asg_desired=0" \
  -var="query_asg_min=0"
cd ..

# 2. Wait for instances to boot and SSH port to open
echo "=== Step 2: Waiting 45 seconds for instances to boot and SSH to start ==="
sleep 45

# 3. Configure the standalone instances using Ansible
echo "=== Step 3: Configuring instances with Ansible ==="
ansible-playbook ha.yml

# 4. Fetch standalone Instance IDs from Terraform
echo "=== Step 4: Fetching instance IDs for AMI baking ==="
cd terraform
VMINSERT_ID=$(terraform output -raw vminsert_instance_id)
VMSELECT_ID=$(terraform output -raw vmselect_instance_id)
cd ..

# 5. Create new AMIs from configured standalone instances
TIMESTAMP=$(date +%s)
INGEST_AMI_NAME="vminsert-baked-${TIMESTAMP}"
QUERY_AMI_NAME="vmselect-baked-${TIMESTAMP}"

echo "=== Step 5: Baking new AMI for Ingestion (vminsert) from $VMINSERT_ID ==="
INGEST_AMI_ID=$(aws ec2 create-image \
  --instance-id "$VMINSERT_ID" \
  --name "$INGEST_AMI_NAME" \
  --no-reboot \
  --query "ImageId" \
  --output text)
echo "Ingestion AMI ID: $INGEST_AMI_ID"

echo "=== Step 5: Baking new AMI for Query (vmselect) from $VMSELECT_ID ==="
QUERY_AMI_ID=$(aws ec2 create-image \
  --instance-id "$VMSELECT_ID" \
  --name "$QUERY_AMI_NAME" \
  --no-reboot \
  --query "ImageId" \
  --output text)
echo "Query AMI ID: $QUERY_AMI_ID"

# 6. Wait for AMIs to be active and ready
echo "=== Step 6: Waiting for AMIs to become active (usually takes 2-3 minutes) ==="
aws ec2 wait image-available --image-ids "$INGEST_AMI_ID" "$QUERY_AMI_ID"
echo "AMIs are active and ready!"

# 7. Run second-stage Terraform Apply to scale ASGs to 1 using the new AMIs
echo "=== Step 7: Scaling ASGs to 1 with the newly baked AMIs ==="
cd terraform
terraform apply -auto-approve \
  -var="ami_id_ingestion=$INGEST_AMI_ID" \
  -var="ami_id_query=$QUERY_AMI_ID" \
  -var="ingestion_asg_desired=1" \
  -var="ingestion_asg_min=1" \
  -var="query_asg_desired=1" \
  -var="query_asg_min=1"
cd ..

echo "=== Deployment Completed Successfully! ==="
