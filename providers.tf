# Runs against the member account, from credentials that live in management. This is the
# cross-account seam the whole three-account structure exists to teach: state and identity in
# management, every workload in dev.
provider "aws" {
  region = var.region

  # Defaults to the read-only role created in iam.tf, so CI plans as the identity that exists for
  # planning. An apply has to create things and a read-only role cannot, so a by-hand run names an
  # administrative role in terraform.tfvars instead. CI has no tfvars, which is what makes the
  # read-only path the one that needs no one to remember it.
  assume_role {
    role_arn = "arn:aws:iam::${var.dev_account_id}:role/${coalesce(var.assume_role_name, module.naming.plan_role)}"
  }

  default_tags {
    tags = module.naming.tags
  }
}

data "aws_caller_identity" "current" {}

# Compares the account the assume-role resolved to against the one named in tfvars. The role ARN
# above is built from dev_account_id, so a run lands in that account or fails at the assume-role.
# A failed check is a warning under the plan and does not stop an apply, so the plan's warnings are
# read before applying. Under `terraform test` a failed check fails the run.
check "running_in_the_dev_account" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.dev_account_id
    error_message = "Credentials resolved to ${data.aws_caller_identity.current.account_id}, not ${var.dev_account_id}."
  }
}

module "naming" {
  source = "git::https://github.com/datapointchris/terraform-aws-lakeworks-naming.git?ref=v0.2.0"

  env        = var.env
  domain     = "platform"
  owner      = "platform-team"
  account_id = var.dev_account_id
}
