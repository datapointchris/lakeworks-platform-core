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
  description = "The one region. An SCP denies the others."
  type        = string
  default     = "us-east-2"
}

variable "dev_account_id" {
  description = "The member account this applies into. providers.tf refuses to run if the assume-role lands elsewhere."
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
    error_message = "raw gets no catalog database. It holds whatever the source gave and is never a table."
  }
}
