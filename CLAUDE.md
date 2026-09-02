# CLAUDE.md

Guidance for Claude Code working in this repository.

Read the README first. It carries what this creates, why `raw` gets no catalog database, why the
cross-repo seam is SSM rather than remote state, and why `prevent_destroy` guards one bucket and
not the other.

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

The module uses hyphens for AWS resource names and underscores for anything SQL touches. That is
not cosmetic — a hyphenated identifier forces backtick quoting in Athena and Spark on every query
forever.

Bumping the pin is an edit in both `providers.tf` and `catalog.tf`. Check they agree; two files
resolving different tags is the failure that hides longest.

## Consumers read SSM, never this state

Pipeline repos find the buckets and database names through `/lakeworks/{env}/platform/...`.
Do not add a `terraform_remote_state` data source for a consumer's benefit, and do not suggest one
as the simpler option. Remote state hands the reader the whole state file rather than the one value
it asked for, and couples it to output names that are this repo's business.

Database parameters are nested by domain so a pipeline can fetch its own layers with one
`GetParametersByPath` without being granted the platform prefix. Flattening that path would take
the grant boundary with it.

## What must not be written under `warehouse/`

Nothing outside a Spark or PyIceberg commit. A plain object copy there produces files the table
metadata does not know about, which is the commonest way a lakehouse is corrupted. If a task seems
to need a direct write, the task is wrong rather than the rule.

## Adding a domain or a layer

`catalog.tf` iterates domains against layers. `raw` is deliberately absent from the layer list and
`platform` is deliberately absent from the domains that get databases — `platform` is
infrastructure rather than a domain team, though it stays a valid tag value for cost attribution.
Adding either back is a decision, not a fill-in-the-gap.

Every catalog change should be checked against `catalog.tftest.hcl`, which runs in CI and under
`terraform test`.
