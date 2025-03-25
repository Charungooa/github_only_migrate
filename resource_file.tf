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
  # Map GitLab environment scopes to GitHub environment names with aliases
  github_env_mapping = {
    "master"      = "master"
    "production"  = "production"
    "prod"        = "production"
    "staging"     = "staging"
    "development" = "development"
    "dev"         = "development"
  }

  # Repository-level unmasked variables (environment_scope == "*")
  all_default_unmasked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    v.key => v
    if !v.masked && v.environment_scope == "*" && v.value != "" && v.value != null
  }

  # Environment-specific unmasked variables
  env_specific_unmasked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    "${lower(v.environment_scope)}-${v.key}" => v
    if !v.masked && v.environment_scope != "*" && v.environment_scope != null && v.value != "" && v.value != null
  }

  # Repository-level masked variables (environment_scope == "*")
  all_default_masked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    v.key => v
    if v.masked && v.environment_scope == "*" && v.value != "" && v.value != null
  }

  # Environment-specific masked variables
  env_specific_masked_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    "${lower(v.environment_scope)}-${v.key}" => v
    if v.masked && v.environment_scope != "*" && v.environment_scope != null && v.value != "" && v.value != null
  }
}

# Store Repository-Level Unmasked Variables as GitHub Variables
resource "github_actions_variable" "all_default_unmasked_vars" {
  for_each = local.all_default_unmasked_secrets

  repository    = data.github_repository.repo.name
  variable_name = each.value.key
  value         = each.value.value
}

# Store Environment-Specific Unmasked Variables in GitHub Environments
resource "github_actions_environment_variable" "env_specific_unmasked_vars" {
  for_each = local.env_specific_unmasked_secrets

  repository    = data.github_repository.repo.name
  environment   = local.github_env_mapping[element(split("-", each.key), 0)]
  variable_name = each.value.key
  value         = each.value.value
  depends_on    = [github_repository_environment.environments]
}

# Store Repository-Level Masked Variables as GitHub Secrets
resource "github_actions_secret" "all_default_masked_secrets" {
  for_each = local.all_default_masked_secrets

  repository       = data.github_repository.repo.name
  secret_name      = each.value.key
  plaintext_value  = each.value.value
}

# Store Environment-Specific Masked Variables in GitHub Environments as Secrets
resource "github_actions_environment_secret" "env_specific_masked_secrets" {
  for_each = local.env_specific_masked_secrets

  repository       = data.github_repository.repo.name
  environment      = local.github_env_mapping[element(split("-", each.key), 0)]
  secret_name      = each.value.key
  plaintext_value  = each.value.value
  depends_on       = [github_repository_environment.environments]
}