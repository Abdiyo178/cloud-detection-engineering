# Created only once the AWS stack has run and its outputs are set in tfvars.
resource "azurerm_sentinel_data_connector_aws_s3" "cloudtrail" {
  count = var.aws_sentinel_role_arn == null ? 0 : 1

  name                       = "aws-cloudtrail-s3"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.lab.workspace_id
  aws_role_arn               = var.aws_sentinel_role_arn
  destination_table          = "AWSCloudTrail"
  sqs_urls                   = [var.aws_cloudtrail_sqs_url]
}

variable "aws_sentinel_role_arn" {
  description = "infra/aws output: sentinel_role_arn"
  type        = string
  default     = null
}

variable "aws_cloudtrail_sqs_url" {
  description = "infra/aws output: cloudtrail_sqs_url"
  type        = string
  default     = null
}
