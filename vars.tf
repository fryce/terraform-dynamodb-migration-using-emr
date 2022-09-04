###########################
# AWS Authentication
###########################

variable "AWS_SOURCE_REGION" {
  default = "ap-southeast-1"
}

variable "aws_source_profile" {
}

variable "AWS_Target_REGION" {
  default = "ap-east-1"
}

variable "aws_target_profile" {
}

##############################
# S3 Info
##############################

variable "emr_bucket_name" {
}

variable "target_emr_bucket_name" {
}

###############################
# DDB
###############################

variable "source_ddb_table_name" {
}

variable "source_ddb_encryption_key" {
}

variable "target_ddb_table_name" {
}

variable "target_ddb_encryption_key" {
}

###############################
# EMR Jar File
###############################

variable "emr_jar_path" {
  default = "./emr-jar/emr-ddb-2.1.0.jar"
}

################################
# EMR Parameter
################################

variable "ddb_throughput_ratio" {
}

variable "emr_export_cluster_name" {
  default = "ddb-export-emr-cluster"
}

variable "emr_import_cluster_name" {
  default = "ddb-import-emr-cluster"
}

variable "emr_master_instance_type" {
  default = "m5.xlarge"
}

variable "emr_master_count" {
  default = 1
}

variable "emr_ebs_size" {
  default = "64"
}

variable "emr_worker_instance_type" {
  default = "m5.xlarge"
}

variable "emr_worker_count" {
  default = 1
}

variable "public_key_path" {
  default = "./key/sample-public-key"
}

variable "private_key_path" {
  default = "./key/sample-private-key.pem"
}

################################
# Environment
################################

variable "environment" {
  default = "ddb-migration-project-001"
}
