# Runs under `terraform test` with no credentials and no state. What it pins is the shape the
# catalog and the parameter paths take, because both are contracts: a pipeline repo reads a
# parameter by path, and renaming one breaks that repo without breaking anything here.

mock_provider "aws" {}

variables {
  env                   = "dev"
  dev_account_id        = "111111111111"
  management_account_id = "222222222222"
  assume_role_name      = "OrganizationAccountAccessRole"
}

# A mocked aws_caller_identity returns a generated account id, which the check block in
# providers.tf compares against dev_account_id. Without this override that check fails every test
# in the repo, for a reason unrelated to whatever is being asserted.
override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

# A mocked policy document returns a generated string, and aws_iam_role rejects it with
# `"assume_role_policy" contains an invalid JSON policy: not a JSON object`. Same problem: a
# failure that says nothing about the assertion that hit it.
override_data {
  target = data.aws_iam_policy_document.plan_trust
  values = { json = "{}" }
}

run "catalog_shape" {
  command = plan

  assert {
    condition     = length(aws_glue_catalog_database.this) == 12
    error_message = "expected 12 databases, got ${length(aws_glue_catalog_database.this)}"
  }

  assert {
    condition     = aws_glue_catalog_database.this["animal_bronze"].name == "lakeworks_dev_animal_bronze"
    error_message = "database name: ${aws_glue_catalog_database.this["animal_bronze"].name}"
  }

  # `platform` is in var.domains for its tag value and is filtered out of the catalog loop.
  assert {
    condition     = !contains(keys(aws_glue_catalog_database.this), "platform_bronze")
    error_message = "platform acquired a database"
  }
}

run "parameter_paths" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.glue_database["animal_bronze"].name == "/lakeworks/dev/platform/glue_database/animal/bronze"
    error_message = "ssm path: ${aws_ssm_parameter.glue_database["animal_bronze"].name}"
  }

  assert {
    condition     = aws_ssm_parameter.lake_bucket.name == "/lakeworks/dev/platform/lake_bucket"
    error_message = "lake bucket path: ${aws_ssm_parameter.lake_bucket.name}"
  }

  assert {
    condition     = aws_ssm_parameter.ops_bucket.name == "/lakeworks/dev/platform/ops_bucket"
    error_message = "ops bucket path: ${aws_ssm_parameter.ops_bucket.name}"
  }
}

# The tags on a per-domain resource come from its own naming instance rather than the provider's
# default_tags, which are the platform instance's. Without this a database for one domain is
# attributed to another, and attribution is what the tags exist for.
run "domain_resources_carry_their_own_domain_and_layer" {
  command = plan

  # `try` in both halves, because the defect this catches is the tags block being absent, and
  # indexing a null map raises a Terraform error rather than failing the assertion. Without it the
  # diagnostic for the exact regression under test is "Attempt to index null value" instead of the
  # tag that was wrong.
  assert {
    condition     = try(aws_glue_catalog_database.this["animal_bronze"].tags["lakeworks:domain"], "<absent>") == "animal"
    error_message = "database domain tag: ${try(aws_glue_catalog_database.this["animal_bronze"].tags["lakeworks:domain"], "<absent>")}"
  }

  assert {
    condition     = try(aws_glue_catalog_database.this["animal_bronze"].tags["lakeworks:layer"], "<absent>") == "bronze"
    error_message = "database layer tag: ${try(aws_glue_catalog_database.this["animal_bronze"].tags["lakeworks:layer"], "<absent>")}"
  }

  assert {
    condition     = try(aws_ssm_parameter.glue_database["animal_bronze"].tags["lakeworks:domain"], "<absent>") == "animal"
    error_message = "parameter domain tag: ${try(aws_ssm_parameter.glue_database["animal_bronze"].tags["lakeworks:domain"], "<absent>")}"
  }
}

# The plan role is what CI assumes. Its name is the naming module's, and the grant in the
# management account matches on `lakeworks-*-plan-role`, so a name that stopped matching that
# pattern would leave CI unable to assume it.
run "plan_role_name_matches_the_grant_pattern" {
  command = plan

  assert {
    condition     = aws_iam_role.plan.name == "lakeworks-dev-platform-plan-role"
    error_message = "plan role name: ${aws_iam_role.plan.name}"
  }

  assert {
    condition     = startswith(aws_iam_role.plan.name, "lakeworks-") && endswith(aws_iam_role.plan.name, "-plan-role")
    error_message = "plan role no longer matches lakeworks-*-plan-role: ${aws_iam_role.plan.name}"
  }
}

run "raw_is_refused_rather_than_described" {
  command = plan

  variables {
    layers = ["raw", "bronze", "silver", "gold", "mart"]
  }

  expect_failures = [var.layers]
}
