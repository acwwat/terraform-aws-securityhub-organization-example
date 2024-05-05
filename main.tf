terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = "~> 1.5"
}

provider "aws" {
  alias = "management"
  # Use "aws configure" to create the "management" profile with the Management account credentials
  profile = "management"
}

provider "aws" {
  alias = "audit"
  # Use "aws configure" to create the "audit" profile with the Audit account credentials
  profile = "audit"
}

data "aws_caller_identity" "audit" {
  provider = aws.audit
}

data "aws_region" "audit" {
  provider = aws.audit
}

data "aws_partition" "audit" {
  provider = aws.audit
}

data "aws_organizations_organization" "this" {
  provider = aws.management
}

resource "aws_securityhub_account" "audit" {
  provider                 = aws.audit
  enable_default_standards = false
}

resource "aws_securityhub_organization_admin_account" "this" {
  provider         = aws.management
  admin_account_id = data.aws_caller_identity.audit.account_id
  depends_on       = [aws_securityhub_account.audit]
}

resource "aws_securityhub_finding_aggregator" "this" {
  provider     = aws.audit
  linking_mode = "ALL_REGIONS"
  depends_on   = [aws_securityhub_account.audit]
}

resource "aws_securityhub_organization_configuration" "this" {
  provider              = aws.audit
  auto_enable           = false
  auto_enable_standards = "NONE"
  organization_configuration {
    configuration_type = "CENTRAL"
  }
  depends_on = [
    aws_securityhub_organization_admin_account.this,
    aws_securityhub_finding_aggregator.this
  ]
}

resource "aws_securityhub_configuration_policy" "this" {
  provider    = aws.audit
  name        = "ExamplePolicy"
  description = "This is an example SHCP."
  configuration_policy {
    service_enabled       = true
    enabled_standard_arns = ["arn:${data.aws_partition.audit.partition}:securityhub:${data.aws_region.audit.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"]
    security_controls_configuration {
      disabled_control_identifiers = ["IAM.6"]
    }
  }
  depends_on = [aws_securityhub_organization_configuration.this]
}

# Some wait time is needed to account for state changes after the configuration policy is disassociated
resource "time_sleep" "aws_securityhub_configuration_policy_this" {
  destroy_duration = "10s"
  depends_on       = [aws_securityhub_configuration_policy.this]
}

resource "aws_securityhub_configuration_policy_association" "org" {
  provider   = aws.audit
  target_id  = data.aws_organizations_organization.this.roots[0].id
  policy_id  = aws_securityhub_configuration_policy.this.id
  depends_on = [time_sleep.aws_securityhub_configuration_policy_this]
}
