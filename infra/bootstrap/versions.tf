terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state on purpose: this root creates the remote state bucket (ADR-007).
  # terraform.tfstate is git-ignored; back it up manually after each apply.
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "urbanmove"
      Env       = "bootstrap"
      Owner     = "amruth"
      ManagedBy = "terraform"
    }
  }
}
