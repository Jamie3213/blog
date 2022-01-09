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

provider  "aws" {
  region = "us-east-1"
  alias  = "useast"

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

data "aws_route53_zone" "hosted_zone" {
    zone_id      = "Z0827073DSZEQ2F7K5PK"
    private_zone = false
 }

/* --------------------------- Base infrastructure -------------------------- */

# S3 buckets
resource "aws_s3_bucket" "primary_bucket" {
  bucket  = "www.jamiehargreaves.co.uk"
  acl     = "public-read"
  policy  = file("policies/s3_public_get_object.json")

  website {
    index_document = "index.html"
    error_document = "404.html"
  }
}

resource "aws_s3_bucket" "redirect_bucket" {
  bucket = replace(aws_s3_bucket.primary_bucket.bucket, "www.", "")

  website {
    redirect_all_requests_to = "https://${aws_s3_bucket.primary_bucket.bucket}"
  }
}

resource "aws_s3_bucket" "logs_bucket" {
  bucket = "s3-jamie-general-logs"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "release_bucket" {
  bucket = "s3-jamie-general-release-artifacts"
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = "/aws/jamie/blog"
}

 # SSL ccertificate and validation
resource "aws_acm_certificate" "cert" {
  provider                  = aws.useast
  domain_name               = aws_s3_bucket.primary_bucket.bucket
  validation_method         = "DNS"
  subject_alternative_names = [aws_s3_bucket.redirect_bucket.bucket]
 }

resource "aws_route53_record" "cnames" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
}

resource "aws_acm_certificate_validation" "cert_validation" {
  provider                = aws.useast
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cnames : record.fqdn]
}

 # CloudFront Distribution
resource "aws_cloudfront_distribution" "distribution" {
  origin {
    origin_id   = "Primary"
    domain_name = aws_s3_bucket.primary_bucket.website_endpoint

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "Primary"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  logging_config {
    bucket          = aws_s3_bucket.logs_bucket.bucket_domain_name
    include_cookies = false
    prefix          = "blog/"
  }

  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2"
  price_class     = "PriceClass_All"

  aliases = [
    aws_s3_bucket.primary_bucket.bucket,
    aws_s3_bucket.redirect_bucket.bucket
  ]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

 # Route 53 records
resource "aws_route53_record" "primary_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = aws_s3_bucket.primary_bucket.bucket
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "redirect_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = ""
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

/* ---------------------------------- CI/CD --------------------------------- */

resource "aws_iam_role" "codebuild_iam_role" {
  name = "iam-${data.aws_region.current.name}-jamie-${var.project}-codebuild-service-role"
  assume_role_policy = file("policies/codebuild_assume_role.json")
}

resource "aws_iam_role_policy" "codebuild_iam_policy" {
  name = "policy-jamie-blog-codebuild"
  role = aws_iam_role.codebuild_iam_role.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateAndPutLogStreams",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${aws_cloudwatch_log_group.log_group.arn}:*"
    },
    {
      "Sid": "S3PutAndGetObject",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": [
        "${aws_s3_bucket.release_bucket.arn}",
        "${aws_s3_bucket.release_bucket.arn}/*",
        "${aws_s3_bucket.primary_bucket.arn}",
        "${aws_s3_bucket.primary_bucket.arn}/*"
      ]
    },
    {
      "Sid": "KmsFullAccess",
      "Effect": "Allow",
      "Action": [
        "kms:*"
      ],
      "Resource": "*"
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
    location  = aws_s3_bucket.release_bucket.bucket
    name      = "build.zip"
    path      = "blog/site/"
    packaging = "ZIP"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.log_group.name
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

    environment_variable {
      name  = "S3_BUILD_BUCKET"
      type  = "PLAINTEXT"
      value = aws_s3_bucket.release_bucket.bucket
    }

    environment_variable {
      name  = "S3_DEPLOY_BUCKET"
      type  = "PLAINTEXT"
      value = aws_s3_bucket.primary_bucket.bucket
    }
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.log_group.name
      stream_name = "site/codebuild/deploy"
    }
  }
}

resource "aws_iam_role" "lambda_iam_role" {
  name = "iam-${data.aws_region.current.name}-jamie-${var.project}-lambda-trigger-codebuild"
  assume_role_policy = file("policies/lambda_assume_role.json")
}

resource "aws_iam_role_policy" "lambda_iam_policy" {
  name = "policy-jamie-blog-lambda-trigger"
  role = aws_iam_role.lambda_iam_role.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateAndPutLogStreams",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*"
    },
    {
      "Sid": "GetBuildArtifacts",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "${aws_s3_bucket.release_bucket.arn}/${var.config_file}"
    },
    {
      "Sid": "StartCodeBuildProjects",
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
  filename      = "../../lambda.zip"
  function_name = "lambda-jamie-blog-trigger-deployment"
  handler       = "app.lambda_handler"
  role          = aws_iam_role.lambda_iam_role.arn
  runtime       = "python3.9"
  architectures = ["arm64"]
  memory_size   = 128
  description   = "Triggers CodeBuild build projects based on S3 change events."
  timeout = 10

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.release_bucket.bucket
      S3_OBJECT_KEY  = var.config_file
    }
  }

  source_code_hash = filebase64sha256("../../lambda.zip")
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.codebuild_trigger.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.release_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.release_bucket.bucket

  lambda_function {
    id                  = "trigger-codebuild-event-lambda"
    lambda_function_arn = aws_lambda_function.codebuild_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "blog/"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}
