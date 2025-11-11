output "s3_bucket"     { value = aws_s3_bucket.images.bucket }
output "dynamo_table"  { value = aws_dynamodb_table.crud_logs.name }
output "sqs_queue_url" { value = aws_sqs_queue.jobs.url }

output "aws_region" {
  value = data.aws_region.current.name
}

output "web_public_ip"     { value = aws_instance.web.public_ip }
output "worker_public_ip"  { value = aws_instance.worker.public_ip }
output "rds_endpoint"      { value = aws_db_instance.rds.address }
output "rds_db_name"       { value = aws_db_instance.rds.db_name }
output "rds_user" {
  value = var.db_user
}
