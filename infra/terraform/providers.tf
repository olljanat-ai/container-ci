provider "azurerm" {
  # `subscription_id` is intentionally not hard-coded. Set ARM_SUBSCRIPTION_ID in
  # the environment, or pass -var/-backend-config from your pipeline.
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {}
}
