variable "env" {
  description = "Deployment environment. One root module per environment; a repo carries no environment of its own."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "region" {
  description = "Region the AWS provider creates every resource in. The region lock that bounds it is an SCP in lakeworks-platform-bootstrap, described in the README under \"Starting from scratch\". The region in backend.tf is the state bucket's, and the aws-region in the plan workflow is where CI exchanges its OIDC token, so neither follows this one."
  type        = string
  default     = "us-east-2"
}

variable "dev_account_id" {
  description = "The member account this applies into. The provider's role ARN is built from it, and a check in providers.tf warns if the resolved account differs."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.dev_account_id))
    error_message = "dev_account_id must be exactly 12 digits."
  }
}

variable "management_account_id" {
  description = "Where state and the CI plan role live. Trusted to assume the read-only plan role created here."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be exactly 12 digits."
  }
}

variable "assume_role_name" {
  description = "Role assumed in the member account. Null resolves to the read-only plan role created here, which is what CI plans as. A by-hand apply names an administrative role in terraform.tfvars, because a read-only role cannot create anything."
  type        = string
  default     = null
}

variable "domains" {
  description = "Tenant domains onboarded to the platform. Domain teams get a Glue database per layer; `platform` is infrastructure and gets none."
  type        = list(string)
  default     = ["animal", "sensor", "clinical", "platform"]
}

variable "layers" {
  description = "Lakehouse layers that get a catalog database. `raw` is deliberately absent — it holds whatever the source gave and is never a table."
  type        = list(string)
  default     = ["bronze", "silver", "gold", "mart"]

  # The absence of `raw` is the point of this list, so it is refused rather than described. Without
  # this the layer model is an invariant that four comments assert and nothing enforces.
  validation {
    condition     = !contains(var.layers, "raw")
    error_message = "layers is ${jsonencode(var.layers)}, set in terraform.tfvars or with -var, and it includes raw. raw gets no catalog database, because it holds whatever the source gave and is never a table. Remove raw from layers and keep only layers the naming module accepts, starting at bronze."
  }
}
