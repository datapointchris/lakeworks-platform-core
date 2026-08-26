# The identity CI plans with. Plan-capable and nothing more: applies are a human act, and a role
# that could apply would make the pull-request review advisory rather than load-bearing.
#
# GitHub Actions federates into `lakeworks-github-plan` in the management account, and that role
# assumes this one to read the dev account. Chaining rather than federating straight into dev keeps
# one trust policy per account instead of one per repository.

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    # The specific role, not the account root. An account-root principal would let any identity in
    # management assume this, which is a much larger set than the one workflow that needs it.
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.management_account_id}:role/lakeworks-github-plan"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = module.naming.plan_role
  description        = "Assumed from the management account to run terraform plan against this account. Cannot apply."
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

# A plan reads every resource in state and writes none of them, which is exactly what this managed
# policy grants. Nothing here needs state-bucket access: the S3 backend authenticates as the
# management role, and only the AWS provider assumes into this one.
resource "aws_iam_role_policy_attachment" "plan_read" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
