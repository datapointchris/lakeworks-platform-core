# One Glue database per (domain, layer). The catalog is where the layer boundary is actually
# drawn — a grant, a query and a job all address a table through it, which is why the buckets do
# not need to be split per layer as well.
#
# `raw` has no database on purpose. It holds whatever the source gave, in whatever shape it
# arrived, and a schema over it would be a claim nothing enforces.

locals {
  # `platform` is infrastructure rather than a domain team, and a medallion stack describes a
  # domain team's pipeline. It stays in var.domains because it is a valid tag value for cost
  # attribution, and is filtered here so it does not acquire four databases nothing writes to.
  catalog_domains = [for domain in var.domains : domain if domain != "platform"]

  # Keyed `{domain}_{layer}` to match the database name's own separator. The key is what every
  # resource below is addressed by, so it appears in state, in plan output and in the SSM path.
  catalog_databases = {
    for pair in setproduct(local.catalog_domains, var.layers) :
    "${pair[0]}_${pair[1]}" => {
      domain = pair[0]
      layer  = pair[1]
    }
  }
}

# A second instance of the naming module, layer-scoped where the one in providers.tf is not.
# `glue_database` and `warehouse_prefix` both return null without a layer, so the platform-level
# instance cannot answer for these.
#
# The tag repeats because Terraform requires `source` to be a literal — it cannot read a variable
# or a local. Both instances move together.
module "catalog_naming" {
  source = "git::https://github.com/datapointchris/terraform-aws-lakeworks-naming.git?ref=v0.2.0"

  for_each = local.catalog_databases

  env        = var.env
  domain     = each.value.domain
  layer      = each.value.layer
  owner      = "platform-team"
  account_id = var.dev_account_id
}

resource "aws_glue_catalog_database" "this" {
  for_each = local.catalog_databases

  name        = module.catalog_naming[each.key].glue_database
  description = "${each.value.layer} tables for the ${each.value.domain} domain."

  # Points at the layer's warehouse prefix, so a CREATE TABLE that names no location still lands
  # where Iceberg owns the paths rather than at the bucket root.
  location_uri = "s3://${aws_s3_bucket.lake.id}/${module.catalog_naming[each.key].warehouse_prefix}"

  # The provider's default_tags are the platform instance's, which would attribute every database
  # to `platform` with no layer. These resources belong to a domain and a layer, and the cost and
  # ownership model reads those two tags. Resource tags win over default_tags on a shared key.
  tags = module.catalog_naming[each.key].tags
}
