#############################################
# Provider
#############################################

provider "aws" { #Source
  region  = var.AWS_SOURCE_REGION
  profile = var.aws_source_profile
}

provider "aws" {
  alias   = "target"
  region  = var.AWS_Target_REGION
  profile = var.aws_target_profile
}

##############################################
# Data Sources
##############################################

data "aws_caller_identity" "source_account" {}

data "aws_caller_identity" "target_account" {
  provider = aws.target
}

data "aws_kms_key" "source_encryption_key" {
  key_id = var.source_ddb_encryption_key
}

data "aws_kms_key" "target_encryption_key" {
  provider = aws.target
  key_id   = var.target_ddb_encryption_key
}

resource "random_id" "random_suffix" {
  byte_length = 6
}

# Generate S3 and EMR names from random suffix
locals {
  source_emr_bucket_name     = "${var.emr_bucket_name}-${lower(var.environment)}-${random_id.random_suffix.hex}"
  target_emr_bucket_name     = "${var.target_emr_bucket_name}-${lower(var.environment)}-${random_id.random_suffix.hex}"
  source_export_cluster_name = "${var.emr_export_cluster_name}-${lower(var.environment)}-${random_id.random_suffix.hex}"
  target_import_cluster_name = "${var.emr_import_cluster_name}-${lower(var.environment)}-${random_id.random_suffix.hex}"
}

#############################################
# Resources - S3 Bucket
#############################################

# S3 bucket - Created in source account, used to store EMR JAR file, exported DynamoDB data, logs
resource "aws_s3_bucket" "emr_storage_bucket" {
  bucket        = local.source_emr_bucket_name
  region        = var.AWS_SOURCE_REGION
  acl           = "private"
  force_destroy = true
  policy        = <<EOF
{
    "Version": "2012-10-17",
    "Id": "",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "${aws_iam_role.target_ddb_migration_emr_ec2_role.arn}"
                ]
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${local.source_emr_bucket_name}",
                "arn:aws:s3:::${local.source_emr_bucket_name}/*"
            ]
        }
    ]
}  
  EOF

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.emr_s3_kms.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# S3 bucket - Created in target account, used to store EMR JAR file, exported DynamoDB data, logs
resource "aws_s3_bucket" "target_emr_storage_bucket" {
  provider      = aws.target
  bucket        = local.target_emr_bucket_name
  region        = var.AWS_Target_REGION
  acl           = "private"
  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.target_emr_s3_kms.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

#############################################
# Resources - KMS Encryption Key
#############################################

resource "aws_kms_key" "emr_s3_kms" {
  description = "Encryption Key for EMR S3"
  policy      = <<EOF
{ 
   "Version":"2012-10-17",
   "Id":"kms-key-policy",
   "Statement":[ 
      { 
         "Sid":"Enable IAM User Permissions",
         "Effect":"Allow",
         "Principal":{ 
            "AWS":[
              "arn:aws:iam::${data.aws_caller_identity.source_account.account_id}:root",
              "arn:aws:iam::${data.aws_caller_identity.target_account.account_id}:root"
            ]
         },
         "Action":"kms:*",
         "Resource":"*"
      }
   ]
}
  EOF
}

resource "aws_kms_key" "target_emr_s3_kms" {
  provider    = aws.target
  description = "Encryption Key for EMR S3"
  policy      = <<EOF
{ 
   "Version":"2012-10-17",
   "Id":"kms-key-policy",
   "Statement":[ 
      { 
         "Sid":"Enable IAM User Permissions",
         "Effect":"Allow",
         "Principal":{ 
            "AWS":[
              "arn:aws:iam::${data.aws_caller_identity.source_account.account_id}:root",
              "arn:aws:iam::${data.aws_caller_identity.target_account.account_id}:root"
            ]
         },
         "Action":"kms:*",
         "Resource":"*"
      }
   ]
}
  EOF
}

#############################################
# Resources - S3 Object
#############################################

# EMR Jar files - Used for both export & import
resource "aws_s3_bucket_object" "ddb-importexport-jar" {
  bucket = aws_s3_bucket.emr_storage_bucket.id
  key    = "jar/emr-ddb-2.1.0.jar"
  source = var.emr_jar_path
  etag   = filemd5(var.emr_jar_path)
}

resource "aws_s3_bucket_object" "target_ddb-importexport-jar" {
  provider = aws.target
  bucket   = aws_s3_bucket.target_emr_storage_bucket.id
  key      = "jar/emr-ddb-2.1.0.jar"
  source   = var.emr_jar_path
  etag     = filemd5(var.emr_jar_path)
}



#################################################
# Resources - IAM for Source 
#################################################

# IAM role - Used by EMR service
resource "aws_iam_role" "ddb_migration_emr_service_role" {
  name = "${var.environment}-emr-service-role-${random_id.random_suffix.hex}"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticmapreduce.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF  
}

resource "aws_iam_role_policy_attachment" "ddb_migration_emr_service_policy" {
  role       = aws_iam_role.ddb_migration_emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# IAM role - Used by EMR instances
resource "aws_iam_role" "ddb_migration_emr_ec2_role" {
  name               = "${var.environment}-emr-ec2-role-${random_id.random_suffix.hex}"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF  
}

resource "aws_iam_instance_profile" "emr_ec2_profile" {
  name = "${var.environment}-emr-ec2-role-${random_id.random_suffix.hex}"
  role = aws_iam_role.ddb_migration_emr_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ddb_migration_emr_ec2_policy" {
  role       = aws_iam_role.ddb_migration_emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

resource "aws_iam_role_policy" "source_emr_ec2_kms_policy" {
  name   = "DDBKMSUsage"
  role   = aws_iam_role.ddb_migration_emr_ec2_role.name
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Effect": "Allow",
            "Resource": [
                "${data.aws_kms_key.source_encryption_key.arn}"
            ]
        }
    ]
}  
  EOF
}


resource "aws_iam_role_policy" "ddb_migration_emr_ec2_profile_kms_policy" {
  name = "${var.environment}-emr-profile-policy"
  role = aws_iam_role.ddb_migration_emr_ec2_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Resource": "${aws_kms_key.emr_s3_kms.arn}",
        "Action": [
            "kms:*"
        ]
    }]
}
EOF
}

#################################################
# Resources - IAM for Target
#################################################

# IAM role - Used by EMR service
resource "aws_iam_role" "target_ddb_migration_emr_service_role" {
  provider = aws.target
  name     = "${var.environment}-emr-service-role-${random_id.random_suffix.hex}"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticmapreduce.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF  
}

resource "aws_iam_role_policy_attachment" "target_ddb_migration_emr_service_policy" {
  provider   = aws.target
  role       = aws_iam_role.target_ddb_migration_emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# IAM role - Used by EMR instances
resource "aws_iam_role" "target_ddb_migration_emr_ec2_role" {
  provider           = aws.target
  name               = "${var.environment}-emr-ec2-role-${random_id.random_suffix.hex}"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF  
}

resource "aws_iam_instance_profile" "target_emr_ec2_profile" {
  provider = aws.target
  name     = "${var.environment}-emr-ec2-role-${random_id.random_suffix.hex}"
  role     = aws_iam_role.target_ddb_migration_emr_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "target_ddb_migration_emr_ec2_policy" {
  provider   = aws.target
  role       = aws_iam_role.target_ddb_migration_emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}


resource "aws_iam_role_policy" "target_ddb_migration_emr_ec2_profile_kms_policy" {
  provider = aws.target
  name     = "KMSUsage"
  role     = aws_iam_role.target_ddb_migration_emr_ec2_role.id

  policy = <<EOF
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect":"Allow",
         "Resource":"${aws_kms_key.emr_s3_kms.arn}",
         "Action":[
            "kms:*"
         ]
      },
      {
         "Action":[
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
         ],
         "Effect":"Allow",
         "Resource":[
            "${aws_kms_key.target_emr_s3_kms.arn}",
            "${data.aws_kms_key.target_encryption_key.arn}"
         ]
      }
   ]
}
EOF
}


#################################################
# Resources - EMR for DynamoDB Export
#################################################

# Export DDB to S3 using EMR in source account
resource "aws_emr_cluster" "export_ddb_emr" {
  depends_on    = [aws_s3_bucket_object.ddb-importexport-jar]
  name          = local.source_export_cluster_name
  release_label = "emr-5.26.0"
  applications  = ["Hadoop", "Hive"]

  ebs_root_volume_size              = 10
  service_role                      = aws_iam_role.ddb_migration_emr_service_role.arn
  termination_protection            = false
  keep_job_flow_alive_when_no_steps = false

  log_uri = "s3://${aws_s3_bucket.emr_storage_bucket.id}/emr/logs/"

  ec2_attributes {
    instance_profile = aws_iam_instance_profile.emr_ec2_profile.name
  }

  master_instance_group {
    name           = "Master"
    instance_type  = var.emr_master_instance_type
    instance_count = var.emr_master_count
    ebs_config {
      size                 = var.emr_ebs_size
      type                 = "gp2"
      volumes_per_instance = 1
    }
  }

  core_instance_group {
    name           = "Core"
    instance_type  = var.emr_worker_instance_type
    instance_count = var.emr_worker_count
    ebs_config {
      size                 = var.emr_ebs_size
      type                 = "gp2"
      volumes_per_instance = 1
    }
  }

  step {
    action_on_failure = "TERMINATE_CLUSTER"
    name              = "Setup Hadoop Debugging"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["state-pusher-script"]
    }
  }

  step {
    action_on_failure = "CONTINUE"
    name              = "DDB Export"
    hadoop_jar_step {
      args = ["org.apache.hadoop.dynamodb.tools.DynamoDbExport", "s3://${local.source_emr_bucket_name}/${var.source_ddb_table_name}Output", "${var.source_ddb_table_name}", "${var.ddb_throughput_ratio}"]
      jar  = "s3://${local.source_emr_bucket_name}/jar/emr-ddb-2.1.0.jar"
    }
  }
}

#################################################
# Resources - EC2 for Tracking Export Progress
#################################################

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.environment}-export-tracker-ec2-role-${random_id.random_suffix.hex}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-export-tracker-ec2-profile-${random_id.random_suffix.hex}"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_policy" "ec2_role_policy" {
  name   = "${var.environment}-export-tracker-role-policy-${random_id.random_suffix.hex}"
  policy = file("./ec2-role-policy.json")
}

resource "aws_iam_role_policy_attachment" "ec2_role_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_role_policy.arn
}


# Key Pair
resource "aws_key_pair" "key_pair" {
  key_name   = "${var.environment}-aws-key-pair-${var.AWS_SOURCE_REGION}-${random_id.random_suffix.hex}"
  public_key = file(var.public_key_path)
}

resource "aws_security_group" "dynamodb_export_tracker_sg" {
  name = "${var.environment}-export-tracker-sg-${random_id.random_suffix.hex}"
  tags = {
    Name = "${var.environment}-export-tracker-sg-${random_id.random_suffix.hex}"
  }
  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_instance" "dynamodb-export-tracker-instance" {
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.dynamodb_export_tracker_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = aws_key_pair.key_pair.key_name

  tags = {
    Name = "${var.environment}-Export-Tracker"
  }

  provisioner "remote-exec" {
    inline = [
      "while ! [ \"`sudo aws emr describe-cluster --cluster-id ${aws_emr_cluster.export_ddb_emr.id} --region ${var.AWS_SOURCE_REGION} |grep 'ALL_STEPS_COMPLETED'`\" ]; do sleep 30; done"
    ]
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }
}

#################################################
# Resources - EMR for DynamoDB Import
#################################################

# Import S3 to DDB using EMR in target account
resource "aws_emr_cluster" "import_ddb_emr" {
  provider      = aws.target
  depends_on    = [aws_s3_bucket_object.ddb-importexport-jar, aws_instance.dynamodb-export-tracker-instance]
  name          = local.target_import_cluster_name
  release_label = "emr-5.26.0"
  applications  = ["Hadoop", "Hive"]

  ebs_root_volume_size              = 10
  service_role                      = aws_iam_role.target_ddb_migration_emr_service_role.arn
  termination_protection            = false
  keep_job_flow_alive_when_no_steps = false

  log_uri = "s3://${aws_s3_bucket.target_emr_storage_bucket.id}/emr/logs/"

  ec2_attributes {
    instance_profile = aws_iam_instance_profile.target_emr_ec2_profile.name
  }

  master_instance_group {
    name           = "Master"
    instance_type  = var.emr_master_instance_type
    instance_count = var.emr_master_count
    ebs_config {
      size                 = var.emr_ebs_size
      type                 = "gp2"
      volumes_per_instance = 1
    }
  }

  core_instance_group {
    name           = "Core"
    instance_type  = var.emr_worker_instance_type
    instance_count = var.emr_worker_count
    ebs_config {
      size                 = var.emr_ebs_size
      type                 = "gp2"
      volumes_per_instance = 1
    }
  }

  step {
    action_on_failure = "TERMINATE_CLUSTER"
    name              = "Setup Hadoop Debugging"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["state-pusher-script"]
    }
  }

  step {
    action_on_failure = "CONTINUE"
    name              = "DDB Import"
    hadoop_jar_step {
      args = ["org.apache.hadoop.dynamodb.tools.DynamoDbImport", "-D", "fs.s3n.endpoint=s3.${var.AWS_SOURCE_REGION}.amazonaws.com", "s3://${local.source_emr_bucket_name}/${var.source_ddb_table_name}Output", "${var.target_ddb_table_name}", "${var.ddb_throughput_ratio}"]
      jar  = "s3://${local.target_emr_bucket_name}/jar/emr-ddb-2.1.0.jar"
    }
  }
}
