output "apply_role_arn" {
  description = "ARN of the apply (RW) deploy role — wire this into the hub's apply_role_arns for this spoke."
  value       = aws_iam_role.apply.arn
}

output "apply_role_name" {
  description = "Name of the apply (RW) deploy role (e.g. ck-org-deploy)."
  value       = aws_iam_role.apply.name
}

output "plan_role_arn" {
  description = "ARN of the plan (RO) deploy role — wire into the hub's plan_role_arns. null for an apply-only spoke."
  value       = local.create_plan ? aws_iam_role.plan[0].arn : null
}

output "plan_role_name" {
  description = "Name of the plan (RO) deploy role (e.g. ck-org-deploy-plan). null for an apply-only spoke."
  value       = local.create_plan ? aws_iam_role.plan[0].name : null
}
