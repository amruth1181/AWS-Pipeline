variable "region" {
  description = "Primary AWS region for the project."
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used to apply the bootstrap."
  type        = string
  default     = "urbanmove"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name."
  type        = string
  default     = "amruth1181/AWS-Pipeline"
}

variable "github_deploy_environment" {
  description = "GitHub Actions environment allowed to assume the deploy role."
  type        = string
  default     = "dev"
}

variable "budget_limit_usd" {
  description = "Monthly cost budget in USD. Credits are excluded, so this tracks real usage."
  type        = number
  default     = 10
}

variable "alert_email" {
  description = "Email address that receives budget alerts. Set it in a git-ignored *.auto.tfvars file."
  type        = string
}
