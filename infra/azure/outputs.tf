output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "workspace_resource_id" {
  value = azurerm_log_analytics_workspace.lab.id
}

# Used as the external ID in the AWS IAM role trust for the CloudTrail connector
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}

output "dcr_sysmon_id" {
  value = azurerm_monitor_data_collection_rule.sysmon.id
}

# Consumed by the AWS host bootstrap for Arc onboarding
output "arc_onboarding_client_id" {
  value = azuread_application.arc_onboarding.client_id
}

output "arc_onboarding_client_secret" {
  value     = azuread_service_principal_password.arc_onboarding.value
  sensitive = true
}
