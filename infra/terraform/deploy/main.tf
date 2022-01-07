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
    description = "The name of the user who created the resource; defaults to 'CodeBuild'."
    default     = "CodeBuild"
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

data "aws_region" "current" {
    name = "eu-west-1"
}

data "aws_route53_zone" "hosted_zone" {
    zone_id      = "Z0827073DSZEQ2F7K5PK"
    private_zone = false
}

/* -------------------------------- Resources ------------------------------- */

# S3 buckets
resource "aws_s3_bucket" "primary_bucket" {
    bucket  = "www.jamiehargreaves.co.uk"
    acl     = "public-read"
    policy  = file("s3_public_get_object_policy.json")

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

    name            = each.value.name
    records         = [each.value.record]
    ttl             = 60
    type            = each.value.type
    zone_id         = data.aws_route53_zone.hosted_zone.zone_id
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

resource "aws_cloudwatch_log_group" "log_group" {
  name = "/aws/jamie/blog"
}
