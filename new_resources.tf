# Key Vault Data Source (Development Only)
data "azurerm_key_vault" "dev_vault" {
  name                = var.key_vault_name_dev
  resource_group_name = var.azure_resource_group_dev
}

# GitLab Project and Variables Data Sources
data "gitlab_project" "project" {
  path_with_namespace = var.gitlab_project_path
}

data "gitlab_project_variables" "secrets" {
  project = data.gitlab_project.project.id
}

# GitHub Repository Data Source
data "github_repository" "repo" {
  full_name = "${var.github_owner}/${var.github_repo_name}"
}

# Create GitHub Environments
resource "github_repository_environment" "environments" {
  for_each = toset(["master", "production", "staging", "development"])

  repository  = data.github_repository.repo.name
  environment = each.key
}

# Local Variables
locals {
  repo_suffix = upper(replace(var.github_repo_name, "/[^a-zA-Z0-9-]/", "-"))

  # Map GitLab environment scopes to GitHub environment names with aliases
  github_env_mapping = {
    "master"      = "master"
    "production"  = "production"
    "prod"        = "production"
    "staging"     = "staging"
    "development" = "development"
    "dev"         = "development"
  }

  # Masked secrets: Only include those explicitly scoped to development or dev
  masked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    "development-${v.key}" => v
    if v.masked && (lower(v.environment_scope) == "development" || lower(v.environment_scope) == "dev")
  }

  # Unmasked secrets for All(default), i.e., environment_scope == "*"
  all_default_unmasked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    v.key => v
    if !v.masked && v.environment_scope == "*" && v.value != "" && v.value != null
  }

  # Unmasked secrets for specific environments, i.e., environment_scope != "*" and not null
  env_specific_unmasked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    "${lower(v.environment_scope)}-${v.key}" => v
    if !v.masked && v.environment_scope != "*" && v.environment_scope != null && v.value != "" && v.value != null
  }
}

# Store Masked Variables in Development Key Vault
resource "azurerm_key_vault_secret" "masked_secrets" {
  for_each = local.masked_secrets

  name         = "${local.repo_suffix}-${replace(replace(each.value.key, "_", "-"), "/[^a-zA-Z0-9-]/", "-")}"
  value        = each.value.value
  key_vault_id = data.azurerm_key_vault.dev_vault.id
  content_type = var.github_repo_name
  tags = {
    environment = "development"
    repository  = local.repo_suffix
  }

  lifecycle {
    ignore_changes = [value]
  }
}

# Store All(default) Unmasked Variables as GitHub Repository Variables
resource "github_actions_variable" "all_default_vars" {
  for_each = local.all_default_unmasked_secrets

  repository    = data.github_repository.repo.name
  variable_name = each.value.key
  value         = each.value.value
}

# Store Environment-Specific Unmasked Variables in GitHub Environments
resource "github_actions_environment_variable" "env_specific_vars" {
  for_each = local.env_specific_unmasked_secrets

  repository    = data.github_repository.repo.name
  environment   = local.github_env_mapping[element(split("-", each.key), 0)]
  variable_name = each.value.key
  value         = each.value.value
  depends_on    = [github_repository_environment.environments]
}