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

variable "config_file" {
  type    = string
  default = "config.yml"
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

resource "aws_iam_role" "codebuild_iam_role" {
  name = "iam-${data.aws_region.current.name}-jamie-${var.project}-codebuild-service-role"

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

resource "aws_iam_role_policy" "codebuild_iam_policy" {
  role = aws_iam_role.codebuild_iam_role.name

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
  service_role   = aws_iam_role.codebuild_iam_role.arn
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
  service_role   = aws_iam_role.codebuild_iam_role.arn
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

resource "aws_iam_role" "lambda_iam_role" {
  name = "iam-${data.aws_region.current.name}-jamie-${var.project}-lambda-trigger-codebuild"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_iam_policy" {
  role = aws_iam_role.lambda_iam_role.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${data.aws_cloudwatch_log_group.log_group.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "${data.aws_s3_bucket.artifact_bucket.arn}/${var.config_file}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:StartBuild"
      ],
      "Resource": "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/deploy-jamie-${var.project}-*"
    }
  ]
}
POLICY
}

resource "aws_lambda_function" "codebuild_trigger" {
  filename      = "../../../lambda.zip"
  function_name = "lambda-jamie-blog-trigger-deployment"
  handler       = "app.lambda_handler"
  role          = aws_iam_role.lambda_iam_role.arn
  runtime       = "python3.9"
  architectures = ["arm64"]
  memory_size   = 128
  description   = "Triggers CodeBuild build projects based on S3 change events."

  environment {
    variables = {
      S3_BUCKET_NAME = data.aws_s3_bucket.artifact_bucket.id
      S3_OBJECT_KEY  = var.config_file
    }
  }

  source_code_hash = filebase64sha256("../../../lambda.zip")
  depends_on = [data.aws_cloudwatch_log_group.log_group]
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.codebuild_trigger.arn
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.artifact_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = data.aws_s3_bucket.artifact_bucket.id

  lambda_function {
    id                  = "trigger-codebuild-event-lambda"
    lambda_function_arn = aws_lambda_function.codebuild_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "blog/"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}
