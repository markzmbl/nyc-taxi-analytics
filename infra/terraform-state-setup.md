# Terraform Remote State — Setup Guide

This document describes how to migrate Terraform state from local to remote backends
for all three cloud providers. Remote state enables team collaboration, prevents
conflicts via state locking, and keeps state securely stored and versioned.

---

## Table of Contents

1. [AWS (S3 + DynamoDB)](#aws-s3--dynamodb)
2. [Azure (Storage Account)](#azure-storage-account)
3. [GCP (GCS)](#gcp-gcs)
4. [Verification](#verification)
5. [Rollback](#rollback)

---

## AWS (S3 + DynamoDB)

### Step 1 — Create the S3 bucket

```bash
# Bucket for storing terraform.tfstate
aws s3api create-bucket \
  --bucket nyc-taxi-tfstate \
  --region us-east-1 \
  --create-bucket-configuration LocationConstraint=us-east-1

# Enable versioning (protects against accidental deletion/corruption)
aws s3api put-bucket-versioning \
  --bucket nyc-taxi-tfstate \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket nyc-taxi-tfstate \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block all public access (security best practice)
aws s3api put-public-access-block \
  --bucket nyc-taxi-tfstate \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### Step 2 — Create the DynamoDB lock table

```bash
aws dynamodb create-table \
  --table-name nyc-taxi-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

The table name and primary key (`LockID`, type `S`) must match exactly — Terraform
uses this for state locking to prevent concurrent `terraform apply` collisions.

### Step 3 — Uncomment the backend block

In `infra/aws/main.tf`, uncomment the `backend "s3"` block inside the `terraform {}`
block. The block is already present, surrounded by detailed comments.

### Step 4 — Migrate existing state

```bash
cd infra/aws
terraform init -migrate-state
```

When prompted: **Answer "yes"** to copy the local `terraform.tfstate` to S3.

After migration, delete the local state file and its backup:
```bash
rm terraform.tfstate terraform.tfstate.backup
```

---

## Azure (Storage Account)

### Step 1 — Create the resource group

```bash
az group create \
  --name rg-nyc-taxi-tfstate \
  --location eastus
```

### Step 2 — Create the Storage Account

```bash
az storage account create \
  --name nyctaxitfstate \
  --resource-group rg-nyc-taxi-tfstate \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2
```

> **Naming constraint:** The storage account name `nyctaxitfstate` must be globally
> unique. If it's already taken, choose another name and update the backend block in
> `infra/azure/main.tf` to match.

### Step 3 — Create the container

```bash
az storage container create \
  --name tfstate \
  --account-name nyctaxitfstate
```

### Step 4 — (Recommended) Enable soft delete for blob versioning

```bash
az storage account blob-service-properties update \
  --account-name nyctaxitfstate \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 7
```

### Step 5 — Uncomment the backend block

In `infra/azure/main.tf`, uncomment the `backend "azurerm"` block inside the
`terraform {}` block.

### Step 6 — Migrate existing state

```bash
cd infra/azure
terraform init -migrate-state
```

When prompted: **Answer "yes"** to copy the local `terraform.tfstate` to Azure.

After migration, delete the local state file and its backup:
```bash
rm terraform.tfstate terraform.tfstate.backup
```

---

## GCP (GCS)

### Step 1 — Create the GCS bucket

```bash
# Create the bucket
gcloud storage buckets create gs://nyc-taxi-tfstate \
  --location us-east1 \
  --uniform-bucket-level-access

# Enable versioning (recovery safety net)
gcloud storage buckets update gs://nyc-taxi-tfstate --versioning
```

> **Naming constraint:** GCS bucket names must be globally unique. If `nyc-taxi-tfstate`
> is taken, use a project-scoped name like `nyc-taxi-tfstate-YOUR_PROJECT_ID` and
> update the backend block in `infra/gcp/main.tf`.

### Step 2 — (Optional) Set a lifecycle rule to retain old versions

```bash
gcloud storage buckets update gs://nyc-taxi-tfstate \
  --lifecycle-file=<(echo '{"rule":[{"action":{"type":"Delete"},"condition":{"numNewerVersions":10}}]}')
```

### Step 3 — Uncomment the backend block

In `infra/gcp/main.tf`, uncomment the `backend "gcs"` block inside the `terraform {}`
block.

### Step 4 — Migrate existing state

```bash
cd infra/gcp
terraform init -migrate-state
```

When prompted: **Answer "yes"** to copy the local `terraform.tfstate` to GCS.

After migration, delete the local state file and its backup:
```bash
rm terraform.tfstate terraform.tfstate.backup
```

---

## Verification

After migration, verify the remote backend is active:

```bash
# This should show no local state file
ls terraform.tfstate  # should fail (file not found)

# This should read state from the remote backend
terraform state list

# Test state locking works (run in two terminals simultaneously):
# Terminal 1:  terraform apply -auto-approve  (or plan)
# Terminal 2:  terraform apply                 (should wait for lock)
```

For AWS, you can also check the DynamoDB table:
```bash
aws dynamodb scan --table-name nyc-taxi-tf-lock --region us-east-1
```

---

## Rollback

If you need to revert to local state (e.g., the remote backend is misconfigured):

### Pull state from remote
```bash
terraform state pull > terraform.tfstate
```

### Comment the backend block again
Re-comment the `backend` block in the respective `main.tf`.

### Re-initialize locally
```bash
terraform init -migrate-state
# Answer "yes" to copy remote state back to local.
```

### Clean up cloud resources (optional)
- **AWS:** Delete the S3 bucket and DynamoDB table via Console or CLI.
- **Azure:** Delete the resource group: `az group delete --name rg-nyc-taxi-tfstate --yes`
- **GCP:** Delete the bucket: `gcloud storage rm -r gs://nyc-taxi-tfstate`
