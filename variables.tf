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
