# lakeworks-platform-core

The README carries what this creates, why `raw` gets no catalog database, why the cross-repo seam
is SSM rather than remote state, and why `prevent_destroy` guards one bucket and not the other.

## Plan, never apply

A person applies this repo. Automation stops at `terraform plan`, and the CI role is plan-capable
by design rather than by oversight. Do not widen it, and do not add an applying workflow.

`terraform plan` needs credentials that can assume into the member account plus a `-backend-config`
for the state bucket. The account ids live in `terraform.tfvars`, which is gitignored;
`terraform.tfvars.example` is the tracked shape and the two are kept in step by hand.

## Never build a name by joining strings

Every name comes from the `terraform-aws-lakeworks-naming` module, pinned by git tag. A
concatenation anywhere in this repo is a bug even when it produces the right string today, because
the module is the only thing that validates the components and the only thing that receives the
account id.

The module uses hyphens for AWS resource names and underscores for anything SQL touches. Keep both
separators; the README's "Names" section says why.

The pin lives in the one `module "naming"` block in `providers.tf`, which `for_each` spreads over
the platform and every catalog database. Reach a name through `module.naming[<key>]` rather than
adding a second block, which would carry a second copy of the tag.

## Consumers read SSM, never this state

Pipeline repos find the buckets and database names through `/lakeworks/{env}/platform/...`.
Do not add a `terraform_remote_state` data source for a consumer's benefit, and do not suggest one
as the simpler option. Keep the database parameters nested by domain rather than flattened. The
README's "SSM" section gives the reason for both.

## What must not be written under `warehouse/`

Nothing outside a Spark or PyIceberg commit. The README's "The lake" section says what a direct
write does. If a task seems to need one, the task is wrong rather than the rule.

## Adding a domain or a layer

`catalog.tf` iterates domains against layers. `raw` is deliberately absent from the layer list and
`platform` is deliberately absent from the domains that get databases. The README's "The catalog"
section gives the reason for each. Adding either back is a decision, not a fill-in-the-gap.

Every catalog change should be checked against `catalog.tftest.hcl`, which runs in CI and under
`terraform test`.
