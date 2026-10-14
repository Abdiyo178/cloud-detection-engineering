terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# ---------------------------------------------------------------------------
# Core: resource group, Log Analytics workspace, Microsoft Sentinel
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "lab" {
  name                = var.workspace_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.daily_quota_gb # ingestion cost ceiling
  tags                = var.tags
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "lab" {
  workspace_id = azurerm_log_analytics_workspace.lab.id
}

# ---------------------------------------------------------------------------
# Endpoint telemetry: Sysmon from Arc-connected Windows hosts -> Event table
# ---------------------------------------------------------------------------

resource "azurerm_monitor_data_collection_rule" "sysmon" {
  name                = "dcr-sysmon"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  kind                = "Windows"

  destinations {
    log_analytics {
      name                  = "sentinel"
      workspace_resource_id = azurerm_log_analytics_workspace.lab.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["sentinel"]
  }

  data_sources {
    windows_event_log {
      name           = "sysmon-operational"
      streams        = ["Microsoft-Event"]
      x_path_queries = ["Microsoft-Windows-Sysmon/Operational!*"]
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.lab]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# Arc onboarding identity: non-human, scoped to one resource group, one role
# ---------------------------------------------------------------------------

resource "azuread_application" "arc_onboarding" {
  display_name = "sp-arc-onboarding"
}

resource "azuread_service_principal" "arc_onboarding" {
  client_id = azuread_application.arc_onboarding.client_id
}

resource "azuread_service_principal_password" "arc_onboarding" {
  service_principal_id = azuread_service_principal.arc_onboarding.object_id
  end_date_relative    = "720h" # 30 days; short-lived by design
}

resource "azurerm_role_assignment" "arc_onboarding" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Azure Connected Machine Onboarding"
  principal_id         = azuread_service_principal.arc_onboarding.object_id
}

# ---------------------------------------------------------------------------
# Cost guardrail
# ---------------------------------------------------------------------------

resource "azurerm_consumption_budget_subscription" "lab" {
  name            = "budget-detection-lab"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.monthly_budget
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }
}
