variable "region" {
  type    = string
  default = "us-east-1"
}

variable "sentinel_workspace_id" {
  description = "Log Analytics workspace GUID (infra/azure output: workspace_customer_id)"
  type        = string
}

variable "sentinel_oidc_tenant" {
  description = "Microsoft's OIDC issuer tenant for Sentinel (commercial cloud)"
  type        = string
  default     = "33e01921-4d64-4f8c-a055-5bdaffd5e33d"
}

variable "sentinel_oidc_audience" {
  description = "Audience Sentinel presents; confirm against the AWS S3 connector page"
  type        = string
  default     = "api://1462b192-27f7-4cb9-8523-0f4ecb54b47e"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type = map(string)
  default = {
    project = "cloud-detection-engineering"
    managed = "terraform"
  }
}
