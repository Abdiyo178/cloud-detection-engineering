variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant ID"
  type        = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-detection-lab"
}

variable "workspace_name" {
  type    = string
  default = "law-detection-lab"
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap for the workspace"
  type        = number
  default     = 1
}

variable "monthly_budget" {
  description = "Monthly budget in billing currency"
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "First day of the current month, RFC3339 (e.g. 2026-10-01T00:00:00Z)"
  type        = string
}

variable "alert_email" {
  description = "Where budget alerts are sent"
  type        = string
}

variable "tags" {
  type = map(string)
  default = {
    project = "cloud-detection-engineering"
    managed = "terraform"
  }
}
