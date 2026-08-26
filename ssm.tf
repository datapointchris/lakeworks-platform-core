# The seam between this state and every pipeline repo's. A consumer reads the parameter it needs
# and learns nothing else.
#
# Deliberately not `terraform_remote_state`. Remote state would give each pipeline read access to
# this entire state file rather than to the one value it asked for, and it would couple every
# consumer to this repo's output names.

resource "aws_ssm_parameter" "lake_bucket" {
  name  = "/lakeworks/${var.env}/platform/lake_bucket"
  type  = "String"
  value = aws_s3_bucket.lake.id
}

resource "aws_ssm_parameter" "ops_bucket" {
  name  = "/lakeworks/${var.env}/platform/ops_bucket"
  type  = "String"
  value = aws_s3_bucket.ops.id
}

# Path-shaped rather than one flat key per database, so a domain can read its own layers with a
# single GetParametersByPath on /lakeworks/{env}/platform/glue_database/{domain}/ without being
# granted the whole platform prefix.
resource "aws_ssm_parameter" "glue_database" {
  for_each = local.catalog_databases

  name  = "/lakeworks/${var.env}/platform/glue_database/${each.value.domain}/${each.value.layer}"
  type  = "String"
  value = aws_glue_catalog_database.this[each.key].name

  # Tagged with the domain and layer it names, matching the database itself, so one query by
  # domain returns both the database and the parameter that points at it.
  tags = module.catalog_naming[each.key].tags
}
