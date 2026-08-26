terraform {
  # Partial config: the bucket name carries the management account id. Supplied at init —
  #   terraform init -backend-config="bucket=lakeworks-tfstate-<management-account-id>"
  backend "s3" {
    key          = "dev/platform/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}
