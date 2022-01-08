terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

/* ----------------------------- Input variables ---------------------------- */

variable "project" {
  type        = string
  description = "An abbreviation for the project the resources relate to."

  validation {
    condition     = can(regex("[a-z]*", var.project))
    error_message = "Project abbreviation must be lower case letters only."
  }
}

variable "created_by" {
  type        = string
  description = "The name of the user who created the resource."
}

variable "artifact_bucket_name" {
  type        = string
  description = "The name of the S3 bucket where build artifacts should be stored."
}

variable "blog_bucket_name" {
  type        = string
  description = "The name of the S3 bucket where the blog is hosted."
}

variable "log_group_name" {
  type        = string
  description = "The name of the CloudWatch Log Group that CodeBuild Log Streams should write to."
}

/* -------------------------------- Providers ------------------------------- */

provider "aws" {
  region = "eu-west-1"

  default_tags { 
    tags = {
      Project     = var.project,
      CreatedBy   = var.created_by
    }
  }
}

/* ------------------------------ Data sources ------------------------------ */

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "artifact_bucket" {
  bucket = var.artifact_bucket_name
}

data "aws_s3_bucket" "blog_bucket" {
  bucket = var.blog_bucket_name
}

data "aws_cloudwatch_log_group" "log_group" {
  name = var.log_group_name
}

/* -------------------------------- Resources ------------------------------- */

resource "aws_iam_role" "iam_role" {
  name = "iam-${data.aws_region.current.name}-dufrain-${var.project}-codebuild-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "iam_policy" {
  role = aws_iam_role.iam_role.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "${data.aws_cloudwatch_log_group.log_group.arn}"
      ],
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "${data.aws_s3_bucket.artifact_bucket.arn}",
        "${data.aws_s3_bucket.artifact_bucket.arn}/*",
        "${data.aws_s3_bucket.blog_bucket.arn}",
        "${data.aws_s3_bucket.blog_bucket.arn}/*"
      ]
    }
  ]
}
POLICY
}

resource "aws_codebuild_project" "build" {
  name           = "build-jamie-blog-site"
  description    = "Builds Hugo blog static files."
  source_version = "main"
  service_role   = aws_iam_role.iam_role.arn
  build_timeout  = 5
  badge_enabled  = true

  source {
    type                = "GITHUB"
    location            = "https://github.com/Jamie3213/blog.git"
    buildspec           = "site/release/buildspec_build.yml"
    report_build_status = true

    git_submodules_config {
      fetch_submodules = true
    }
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }

  artifacts {
    type      = "S3"
    location  = data.aws_s3_bucket.artifact_bucket.id
    name      = "build.zip"
    path      = "blog/site/"
    packaging = "ZIP"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = data.aws_cloudwatch_log_group.log_group.name
      stream_name = "site/codebuild/build"
    }
  }
}

resource "aws_codebuild_webhook" "webhook" {
  project_name = aws_codebuild_project.build.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "main"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "site/*"
    }
  }
}

resource "aws_codebuild_project" "deploy" {
  name           = "deploy-jamie-blog-site"
  description    = "Deploy the static Hugo blog to Amazon S3."
  source_version = "main"
  service_role   = aws_iam_role.iam_role.arn
  build_timeout  = 5

  source {
    type                = "GITHUB"
    location            = "https://github.com/Jamie3213/blog.git"
    buildspec           = "site/release/buildspec_deploy.yml"
    report_build_status = true

    git_submodules_config {
      fetch_submodules = true
    }
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = data.aws_cloudwatch_log_group.log_group.name
      stream_name = "site/codebuild/deploy"
    }
  }
}

resource "aws_cloudwatch_event_rule" "deploy_trigger" {
  name        = "trigger-jamie-blog-deploy"
  description = "Triggers the Blog deploy CodeBuild project when the build artifacts are updated."
}
