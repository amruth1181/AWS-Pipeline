output "state_bucket" {
  description = "S3 bucket holding remote state for every other Terraform root."
  value       = aws_s3_bucket.tfstate.bucket
}

output "gha_plan_role_arn" {
  description = "Role GitHub Actions assumes for terraform plan on pull requests."
  value       = aws_iam_role.gha_plan.arn
}

output "gha_deploy_role_arn" {
  description = "Role GitHub Actions assumes for deploys from the dev environment."
  value       = aws_iam_role.gha_deploy.arn
}

output "budget_name" {
  description = "Name of the monthly AWS Budget."
  value       = aws_budgets_budget.monthly.name
}
