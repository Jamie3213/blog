terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 3.0"
        }
    }
}

provider "aws" {
    region = "eu-west-1"
}

resource "aws_route53_zone" "hosted_zone" {
    name = "jamiehargreaves.co.uk"
}
