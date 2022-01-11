+++
author = "Jamie Hargreaves"
title = "Static Blogging with AWS"
date = "2022-01-11"
description = "Deploying a static blog using Hugo and AWS."
tags = [
    "aws",
    "amazon s3",
    "amazon cloudfront",
    "amazon route 53",
    "aws codebuild",
    "aws eventbridge",
    "hugo",
    "markdown"
]
+++

This article walks through the process to build and deploy a static blog (or any static website), using Hugo, and AWS services like Amazon S3 and CloudFront. In addition, the article shows how to utilise Terraform to deploy the necessary AWS resources as code, along with a walk-through of an automated CI/CD pipeline using AWS CodeBuild for deploying new posts or changes to the website.
