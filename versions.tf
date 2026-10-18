terraform {
  # 1.10 is the first release whose S3 backend accepts `use_lockfile`, which backend.tf sets.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
