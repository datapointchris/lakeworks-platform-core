# lakeworks-platform-core

The lakehouse itself, in the `dev` account: the storage every pipeline writes into, and the
platform-level resources they all share. It is Terraform, applied by a person and planned by CI.

It is the second apply in the stack. `lakeworks-platform-bootstrap` comes first and creates the
organization, the `dev` account, the state bucket and the CI identity. Pipeline repos come after
it. Each writes into the lake this repo creates.

```text
  bootstrap        organization · dev account · state bucket · OIDC · CI plan role · SCP · budgets
      │
      ▼
  platform-core    the lake · the catalog · the shared parameters
      │
      ▼
  pipeline repos   one per pipeline, or per domain where the infrastructure is shared
```

**Every run starts from credentials in the management account and assumes a role in `dev`.** That
seam is the point of the account structure. State and identity live in management. Every workload
lives in a member account, where service control policies apply. They never apply to the management
account.

## Install

Terraform and git are all the local checks need. Nothing below reaches AWS.

```bash
git clone https://github.com/datapointchris/lakeworks-platform-core.git
cd lakeworks-platform-core
terraform init -backend=false   # the AWS provider and the naming module, with no state and no credentials
terraform test                  # the contracts a pipeline repo depends on, against a mocked provider
```

CI runs the same two commands on every pull request. The tests pin the database names, the
parameter paths, the domain and layer tags, the plan role's name, and the refusal of `raw`.

## Starting from scratch

The first apply needs three things the bootstrap leaves in place: the `dev` account, the state
bucket, and an administrative credential in the management account.

```bash
export AWS_PROFILE=<management-profile>          # the credential bootstrap was applied with
aws sts get-caller-identity                       # confirm it names the management account
cp terraform.tfvars.example terraform.tfvars      # then fill in both account ids

# The backend is partial: the bucket name carries the management account id.
terraform init -backend-config="bucket=lakeworks-tfstate-<management-account-id>"

terraform plan -out=core.tfplan                   # read every resource, and every warning
terraform apply core.tfplan                       # creates the plan role CI needs, among the rest
terraform output                                  # the two buckets, each catalog database, the plan role
```

**The account ids are not in the repo.** `terraform.tfvars` is gitignored, and
`terraform.tfvars.example` is the tracked shape.

**The first apply assumes `OrganizationAccountAccessRole`.** The example file sets it. It is the
role bootstrap lets the management account assume into `dev`. Leave `assume_role_name` out and the
provider assumes the read-only plan role instead. That role can plan and cannot create, and it does
not exist until this apply creates it. CI has no `terraform.tfvars`, so it takes that default and
plans as the read-only role. The safe path is the one nobody has to remember.

**State lives in the management account.** It sits at `dev/platform/terraform.tfstate` in the
bootstrap's state bucket. The S3 backend locks it with a lock file beside it, so no DynamoDB table
is involved.

**The account is named once, in `dev_account_id`.** The provider builds the role ARN from it, so a
run lands in that account or fails at the assume-role. A `check` block in `providers.tf` compares
the resolved account against it as well. Terraform reports a failed check as a warning under the
plan and goes on to apply, so the warnings are read before the apply.

**The region lock lives in bootstrap.** An SCP on `dev` denies every region but `us-east-2` and
`us-east-1`, outside the global services. A plan placing a resource anywhere else is that SCP about
to reject it.

## The lake — two buckets, split by data and operations rather than by layer

```text
S3 lakeworks-<env>-lake-<account>    versioned · encrypted · prevent_destroy
    raw/{domain}/{pipeline}/          whatever the source gave
    warehouse/{layer}/{domain}/       Iceberg-managed
    tmp/                              expires after 7 days
S3 lakeworks-<env>-ops-<account>     encrypted
    artifacts/ · logs/
    athena-results/                   expires after 30 days
    terraform-plans/                  expires after 30 days
```

Both buckets block public access outright and abort incomplete multipart uploads after seven days.

**Two buckets, not one per layer.** Lake Formation grants at table granularity anyway. A bucket per
layer multiplies the policy surface for a boundary the catalog already draws. The split that pays is
data from operations: one policy can then be strict and the other permissive.

**Nothing outside a Spark or PyIceberg commit writes under `warehouse/`.** A stray `aws s3 cp` there
produces files the table metadata does not know about. That is the commonest way a lakehouse is
corrupted.

**`prevent_destroy` guards the lake and not the ops bucket.** Losing query results and plan output
costs a re-run. Losing the lake is the whole platform. A plan that would destroy the lake bucket
fails instead.

**The expiries keep unwatched prefixes from growing.** A job writes `tmp/` mid-run and never lists
it again. Athena writes a result set for every query, including the ones nobody keeps.

## The catalog — one Glue database per domain team and layer, starting at bronze

```bash
terraform output glue_databases   # every lakeworks_<env>_<domain>_<layer>, keyed {domain}_{layer}
```

**`raw` has no catalog database.** It holds whatever the source gave, in whatever shape it arrived.
A schema over it would be a claim nothing enforces, so the catalog starts at `bronze`.
`variables.tf` refuses `raw` in the layer list rather than leaving its absence to a comment.

**`platform` has no catalog databases either.** It is infrastructure rather than a domain team, and
a medallion stack describes a domain team's pipeline. It stays a valid `lakeworks:domain` tag value,
because platform resources still need cost attribution.

**Each database is located at its layer's warehouse prefix.** A `CREATE TABLE` that names no
location lands where Iceberg owns the paths, not at the bucket root.

**Each database and its parameter carry their own domain and layer tags.** The provider's default
tags are the platform's. Left to those, every database would be attributed to `platform` with no
layer.

The domains and layers are `domains` and `layers` in `variables.tf`. The naming module validates
both against its own lists, so a domain it does not know starts as a change there.

## Names — computed by one module, never by joining strings

```text
lakeworks-dev-lake-<account>    AWS resource names take hyphens
lakeworks_dev_animal_bronze     anything SQL touches takes underscores
```

Every name comes from `terraform-aws-lakeworks-naming`, pinned by tag. Nothing here builds a name by
joining strings, even where the join would produce the right string. The module validates every
component, and it is where the account id enters a name.

The two separators are deliberate. A hyphenated identifier forces quoting in Athena and Spark on
every query, rather than once at the point it is named.

The module is instantiated twice at one tag. `providers.tf` holds the platform-level instance.
`catalog.tf` holds a layer-scoped instance per database, because a database name and a warehouse
prefix need a layer. Terraform takes `source` only as a literal, so a pin bump edits both files and
the two tags must agree.

## SSM — the seam pipeline repos read, never this state

```text
/lakeworks/{env}/platform/lake_bucket
/lakeworks/{env}/platform/ops_bucket
/lakeworks/{env}/platform/glue_database/{domain}/{layer}
```

**A pipeline repo reads a parameter, never `terraform_remote_state`.** Remote state would give every
consumer read access to this whole state file rather than to the one value it asked for. It would
also couple each consumer to output names that are this repo's business. A parameter grants exactly
one value. This state's outputs are for a person at a terminal.

**The database paths are nested by domain.** A pipeline reads its own layers with one
`GetParametersByPath` on `/lakeworks/{env}/platform/glue_database/{domain}/`. It needs no grant on
the platform prefix as a whole.

## Plan on PR — CI plans as a read-only role and never applies

Applies are run by hand. CI posts a plan on every pull request so the diff is read before it is
real. A role that could apply would make that review advisory.

These repository variables are set once. None is a secret, and none belongs in a tracked file: an
account id in a workflow is a permanent disclosure in a public repo.

```bash
gh variable set AWS_PLAN_ROLE_ARN     --body "arn:aws:iam::<management-account-id>:role/lakeworks-github-plan"
gh variable set TF_STATE_BUCKET       --body "lakeworks-tfstate-<management-account-id>"
gh variable set DEV_ACCOUNT_ID        --body "<dev-account-id>"
gh variable set MANAGEMENT_ACCOUNT_ID --body "<management-account-id>"
```

Three things gate the plan job, and they fail at two different steps.

```text
credentials step          the OIDC trust condition on the CI role
                            matches the subject GitHub presents
                            ↳ lives in bootstrap

terraform plan step       the CI role may sts:AssumeRole onto this account
                            the grant matches lakeworks-*-plan-role
                            ↳ lives in bootstrap

                          the read-only role exists, and trusts the CI role
                            ↳ this repo's first apply
```

**Until the first apply, every plan fails at the `terraform plan` step.** The read-only role does
not exist yet.

**The subject GitHub presents carries a numeric owner id and repository id.** A trust condition
written for a plain `owner/repo` string never matches it.

**The plan role's name is not free to change.** The grant matches on `lakeworks-*-plan-role`. A
rename that left that pattern would leave CI unable to assume the role, so `catalog.tftest.hcl`
asserts the shape.

**The plan role trusts one role in management, not the account root.** An account-root principal
would let any identity in management assume it.

**The plan role carries `ReadOnlyAccess`, broader than this state needs.** The state holds S3, Glue,
IAM and SSM. A narrower policy that missed a permission would surface as an `AccessDenied` mid-plan,
which reads at a glance like the cross-account hop failing.

The first two gates live in the bootstrap repo. Nothing here substitutes for them. Pointing this
workflow at an administrative role instead would give a compromised workflow that access.

`.github/workflows/plan.yml` posts the plan whether or not it succeeded, then fails the job if it
did not. `.github/workflows/validate.yml` runs `terraform test` and the hooks in
`.pre-commit-config.yaml` with no credentials at all. A formatting mistake is caught without
touching real state.

## Separate from bootstrap, so CI never holds Organizations permissions

This repo is planned in GitHub Actions. If account creation lived here too, the CI role would need
`organizations:CreateAccount`, and a compromised workflow could create AWS accounts on the bill.

Terraform draws the same line. It needs a provider's configuration before it plans, so a provider
cannot assume into an account the same apply creates. `dev` has to exist before this repo's
provider can assume into it.
