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

  # All variables for repository level (environment_scope == "*")
  all_default_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    v.key => v
    if v.environment_scope == "*" && v.value != "" && v.value != null
  }

  # All variables for specific environments (environment_scope != "*")
  env_specific_secrets = {
    for v in data.gitlab_project_variables.secrets.variables :
    "${lower(v.environment_scope)}-${v.key}" => v
    if v.environment_scope != "*" && v.environment_scope != null && v.value != "" && v.value != null
  }
}

# Store All (default) Variables as GitHub Repository Secrets
resource "github_actions_secret" "all_default_secrets" {
  for_each = local.all_default_secrets

  repository       = data.github_repository.repo.name
  secret_name      = each.value.key
  plaintext_value  = each.value.value
}

# Store Environment-Specific Variables as GitHub Environment Secrets
resource "github_actions_environment_secret" "env_specific_secrets" {
  for_each = local.env_specific_secrets

  repository       = data.github_repository.repo.name
  environment      = local.github_env_mapping[element(split("-", each.key), 0)]
  secret_name      = each.value.key
  plaintext_value  = each.value.value
  depends_on       = [github_repository_environment.environments]
}