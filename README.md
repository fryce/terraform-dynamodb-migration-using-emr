# Implement Terraform For DynamoDB Migration Using EMR

This module supports to one-off migrate **one DynamoDB table** between different AWS regions from one AWS account to another.

For migration between different source & target accounts sets, need other isolate executions.


## Step 1. Check Prerequisites

- Assume Target DynamoDB table including secondary indexes is ready. (Terraform here won't create for you.)
- Assume both source and target DDB is encrypted by **KMS CMK**.
- Make sure existed KMS key policy allows the keys to be accessed from target account:
  1. In source account, go to KMS console.
  2. Choose existed CMK used by DynamoDB tables and edit. 
  3. In **Other AWS accounts** area, add target AWS account. Then Terraform here will help you on IAM settings so you don't need to worry about this part.
- Increase **RCU** of source DynamoDB table and **WCU** of target DynamoDB table beforehand for more throughput.
- Edit "~/.aws/credentials" to add profile name, access key and secret key. It will be used as Terraform variables. e.g.
```   
   ...
   [source_account_profile]
   aws_access_key_id=XXXXXXXXXXXXXXXXX
   aws_secret_access_key=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ...
```

## Step 2. Configure parameters

Download migration source:

```
$ git clone git@github.com:fryce/terraform-dynamodb-migration-using-emr.git
$ cd ./terraform-dynamodb-migration-using-emr
```


Configure **tfvars** file (e.g. terraform.tfvars)  under folder [terraform-dynamodb-migration-using-emr](https://github.com/fryce/terraform-dynamodb-migration-using-emr) before *terraform apply*:

- AWS Credentials
    - **aws_source_profile**:
      The AWS credential profile name associated with source account
    - **aws_target_profile**:
      The AWS credential profile name associated with target account
    
- S3 related Information 
    - **emr_bucket_name**:
      The bucket name prefix which will be created in ***source*** account and used to store EMR stuffs
    - **target_emr_bucket_name**:
      The bucket name prefix which will be created in ***target*** account and used to store EMR stuffs
    
- EMR Parameter
    - **ddb_throughput_ratio**: 
      The ratio that you want EMR to use on WCU/RCU of your DDB
    - **emr_master_instance_type**: (Optional, default to m5.xlarge) 
      The instance size used for EMR master node (Check https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-supported-instance-types.html) 
      ** Note that HK region doesn't support m4 instance*
    - **emr_master_count**: (Optional, default to 1) 
  The number of EMR master node to launch
    - **emr_ebs_size**: (Optional, default to 64) 
      The EBS size that every EMR node will use
    - **emr_worker_instance_type**: (Optional, default to m5.xlarge)
      The instance size used for EMR worker nodes (Check https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-supported-instance-types.html) *Noted that HK region doesn't support m4 instance*
    - **emr_worker_count**: (Optional, default to 1)
      The number of EMR worker node to launch. Consider setting to a higher number depedning on the source table size.
    
- DDB Parameter
    - **source_ddb_table_name**: The source DDB table where EMR will export from
    - **source_ddb_encryption_key**: The KMS CMK key id used to encrypt source DDB
    - **target_ddb_table_name**: The target DDB table name where EMP will import to
    - **target_ddb_encryption_key**: The KMS CMK key id used to encrypt target DDB



## Step 3.  Deploy & Delete resources

1. Deploy migration resources:

   `terraform init`

   `terraform plan -out <OUTFILENAME>`

   `terraform apply <OUTFILENAME>` 

2. Delete migration resources:   **Data won't be deleted.**

   `terraform destroy`



## Output from Terraform

- **Import_EMR_Cluster_ID**: The import EMR cluster ID when applicable
- **Import_EMR_Cluster_Name**: The import cluster name when applicable
- **Export_EMR_Cluster_ID**: The export EMR cluster ID when applicable
- **Export_EMR_Cluster_Name**: The export cluster name when applicable



## Resources created by Terraform

- One S3 bucket with corresponding KMS key used by EMR in source account 
- One S3 bucket with corresponding KMS key used by EMR in target account
- EMR JAR files uploaded to above two S3 buckets
- EMR Service roles and EMR EC2 roles for both source and target account
- One EMR cluster for exporting DynamoDB in source account
- One EMR cluster for importing DynamoDB in target account
- One EC2 instance for tracking progress of exporting DynamoDB in source account, and its corresponding IAM role/policy

