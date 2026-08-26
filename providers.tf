# Runs against the member account, from credentials that live in management. This is the
# cross-account seam the whole three-account structure exists to teach: state and identity in
# management, every workload in dev.
provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.dev_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = module.naming.tags
  }
}

data "aws_caller_identity" "current" {}

# Refuses to run if the assume-role landed somewhere other than the account named in tfvars.
# Creating a lake in the wrong account is not something to find out from a bill.
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
