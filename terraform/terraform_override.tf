terraform {
  backend "s3" {
    region               = "us-east-1"
    bucket               = "filoz-github-mgmt-filozone"
    key                  = "terraform.tfstate"
    workspace_key_prefix = "org"
    use_lockfile         = true
  }
}
