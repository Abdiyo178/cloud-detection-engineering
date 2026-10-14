# Both feed the Sentinel AWS S3 connector in infra/azure
output "sentinel_role_arn" {
  value = aws_iam_role.sentinel.arn
}

output "cloudtrail_sqs_url" {
  value = aws_sqs_queue.cloudtrail.url
}
