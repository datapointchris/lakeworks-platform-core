# lakeworks-platform-core

The lakehouse itself, in the `dev` account: the storage every pipeline writes into, and the
platform-level resources they all share.

**Applied against `dev` from credentials that live in the management account.** That cross-account
seam is the point of the three-account structure — state and identity in management, every workload
in a member account that service control policies can actually reach.

## Where this sits

`lakeworks-platform-bootstrap` creates the organization, the `dev` account, the state bucket, the
region-lock SCP and the GitHub OIDC provider. It is run by hand, a handful of times ever.

This repo is the next apply, and the first one that creates anything a pipeline uses. Pipeline repos
come after it and are separate again.

```text
  bootstrap        organization · dev account · state bucket · OIDC · SCP
      │
      ▼
  platform-core    the lake · the catalog · the shared parameters
      │
      ▼
  pipeline repos   one per domain, each writing into the lake
```

The split from bootstrap is about CI credentials rather than tidiness. This repo runs in GitHub
Actions. If account creation lived here too, the CI role would need `organizations:CreateAccount`,
and a compromised workflow could create AWS accounts on the bill.

## What it creates

```text
DEV ACCOUNT
  S3 lakeworks-<env>-lake-<account>    versioned · encrypted · prevent_destroy
      tmp/                              expires after 7 days
  S3 lakeworks-<env>-ops-<account>    encrypted
      athena-results/                   expires after 30 days
      terraform-plans/                  expires after 30 days
```

Both buckets block public access outright and abort incomplete multipart uploads after seven days.

**Two buckets, not one per layer.** Lake Formation grants at table granularity anyway, so a bucket
per layer multiplies the policy surface for a boundary the catalog already draws. The split that
pays is data from operations: one policy can then be strict and the other permissive.

**`prevent_destroy` guards the lake and not the ops bucket.** Losing query results and plan output
costs a re-run. Losing the lake is the whole platform.

## Names come from a module, never from concatenation

Every name is computed by `terraform-aws-lakeworks-naming`, pinned by tag. Nothing in this repo
builds a name by joining strings.

The module uses two separators on purpose. AWS resource names take hyphens. Anything SQL touches
takes underscores, because a hyphenated identifier forces quoting in Athena and Spark on every query
rather than once at the point it is named.

## First run

The two account ids are not in the repo. `terraform.tfvars` is gitignored and
`terraform.tfvars.example` carries the shape.

```bash
cp terraform.tfvars.example terraform.tfvars    # fill in the two account ids

# The backend is partial: the state bucket name carries the management account id,
# so it is supplied at init rather than written into backend.tf.
terraform init -backend-config="bucket=lakeworks-tfstate-<management-account-id>"

terraform plan -out=core.tfplan                 # review this
terraform apply core.tfplan
```

`providers.tf` carries a `check` block that refuses to run if the assume-role resolved to an account
other than the one named in `terraform.tfvars`. Creating a lake in the wrong account is not
something to find out from a bill.

An SCP on the `dev` account denies every region but `us-east-2` and `us-east-1`. A plan showing a
resource anywhere else is that SCP about to reject it.

## Plan on PR

Applies are run by hand. CI exists to post a plan on a pull request so the diff is read before it is
real — a role that could apply would make that review advisory.

Three repository variables have to be set once. None is a secret, and none belongs in a tracked
file: an account id in a workflow is a permanent disclosure in a public repo.

```bash
gh variable set AWS_PLAN_ROLE_ARN --body "arn:aws:iam::<management-account>:role/lakeworks-github-plan"
gh variable set TF_STATE_BUCKET   --body "lakeworks-tfstate-<management-account>"
gh variable set DEV_ACCOUNT_ID    --body "<dev account id>"
```

`.github/workflows/plan.yml` assumes the plan-only role in management, runs `terraform plan`, and
posts the output to the pull request. `.github/workflows/validate.yml` runs `fmt`, `validate` and
`terraform test` with no credentials at all, so a formatting mistake is caught without touching real
state.
