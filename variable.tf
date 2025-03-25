variable "gitlab_project_path" {
  description = "GitLab project path (namespace/project)"
  type        = string
}

variable "github_owner" {
  description = "GitHub username or organization name where repo exists"
  type        = string
}

variable "github_repo_name" {
  description = "Name of the GitHub repository"
  type        = string
}

variable "gitlab_token" {
  description = "GitLab Personal Access Token for API access"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}