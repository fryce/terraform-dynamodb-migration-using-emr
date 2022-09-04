output "Import_EMR_Cluster_ID" {
  description = "The ID of the EMR Cluster"
  value       = aws_emr_cluster.import_ddb_emr.id
}

output "Import_EMR_Cluster_Name" {
  description = "The name of the EMR Cluster"
  value       = aws_emr_cluster.import_ddb_emr.name
}

output "Export_EMR_Cluster_ID" {
  description = "The ID of the EMR Cluster"
  value       = aws_emr_cluster.export_ddb_emr.id
}

output "Export_EMR_Cluster_Name" {
  description = "The name of the EMR Cluster"
  value       = aws_emr_cluster.export_ddb_emr.name
}
