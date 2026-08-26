# Outputs are for a person at a terminal and for the next apply in this repo. A pipeline repo reads
# SSM instead — see ssm.tf for why the seam is a parameter rather than this state file.

output "lake_bucket" {
  description = "The lakehouse bucket."
  value       = aws_s3_bucket.lake.id
}

output "ops_bucket" {
  description = "Artifacts, logs, query results and plan JSON."
  value       = aws_s3_bucket.ops.id
}

output "glue_databases" {
  description = "Catalog database name for each domain team and layer, keyed {domain}_{layer}."
  value       = { for k, db in aws_glue_catalog_database.this : k => db.name }
}

output "plan_role_arn" {
  description = "The role CI plans as. providers.tf resolves it by default, so nothing has to be configured to point at it; this is here to confirm what was created and to read its name back."
  value       = aws_iam_role.plan.arn
}
