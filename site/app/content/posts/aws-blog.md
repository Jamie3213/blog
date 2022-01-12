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
    "amazon certificate manager",
    "hugo",
    "markdown",
    "terraform",
    "ci/cd"
]
+++

!["Header showing an image of a bookshelf"](/images/blog/header.jpg)

## Overview

This post walks through the process of building and deploying a static blog (or any static website, for that matter), using [Hugo](https://gohugo.io), and AWS services like Amazon S3 and CloudFront. In addition, it shows how to utilise [Terraform](https://www.terraform.io) to deploy the necessary AWS resources as code, along with a walk-through of an automated CI/CD pipeline using AWS CodeBuild for deploying new posts or changes to the website.

Before we get into things, you can find the full source code for this blog [on GitHub](https://github.com/Jamie3213/blog).

## Defining the Solution

We've established that we're going to build a blog or some other website, but the key here is that we're building a *static* site, i.e. we're building a site that doesn't have dynamic content which means that it doesn't utilise server-side processing to do things like calling REST APIs or interacting with databases - once we've written our content, it doesn't change and it doesn't need to rely on any external resources. Whilst this is restrictive for some things (Amazon wouldn't be much use to anyone if it were static, for example), it's perfect for a blog and it means that despite the fact that I know very little about good web development, I can very quickly build an aesthetically pleasing blog with minimal effort.

In addition to being much easier to build, the static nature of our site means it'll also be much easier (and cheaper), to host. For hosting, we're going to utilise Amazon S3, a cloud object store that supports servicing static web content, and Amazon CloudFront, a Content Delivery Network (CDN). Whilst not strictly necessary, the use of a CDN lets us cache our static content on AWS edge nodes for better end-user performance, rather than making our users go all the way to S3 every time and, since it's very cheap for our use case, we'll use it - if you're interested, you can read more about how CloudFront handles requests in the [documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/HowCloudFrontWorks.html). Potentially more importantly, the use of CloudFront is also required if we want to enable connection to our site over HTTPS.

Overall, our solution architecture is fairly straight forward and is going to look like the diagram below, and we'll discuss each component as we go.

!["Blog Solution Architecture Diagram"](/images/blog/solution_architecture.png)

## The Blog Itself

### Choosing a Framework

Okay, so we've seen the overall solution, but the first question is how am I going to build the actual blog? Well, there are numerous options and for a while I toyed around with the idea of building a custom site in [React.js](https://reactjs.org) (and actually made a start on it), however as I was doing so I realised two things:

* Firstly, web-development isn't my forté; I know enough JavaScript to get by, but when it comes to responsive design and all the other intricacies of building a site that will reliably work across a range of devices, I'm out of my depth.
* Secondly, whilst building your own React application (or using any number of other frameworks like Next.js or AngularJS), is a great way to learn more about web development, it's also fairly time consuming if you're new to it and I found it detracted from the purpose of the project, which was to start a blog, not to learn web development.

As such, if you're mostly interested in quickly getting something up and running and actually starting to add content to your blog, I'd recommend the option I ultimately went with: Hugo. Hugo is an open-source web framework specifically designed with static web content in mind and with tons of community support for responsive themes which makes development extremely easy, even if (like me), you've little to no web development experience. In addition, blog posts can be written in plain Markdown whilst also supporting some nice extensions called [shortcodes](https://gohugo.io/content-management/shortcodes/) if you want to get a bit more creative.

### Building the Blog

The basic structure we're going to use for the project is as follows:

```zsh
├── infra
└── site
    ├── app
    └── release
```

I won't go over the steps to install Hugo and set up a new site since I'd just be re-hashing what's already covered in the [Quick-Start guide](https://gohugo.io/getting-started/quick-start), so if you are using Hugo, have a read through the guide and you should be up and running with a new site in a few minutes. Once you have everything ready, you can use the following commands to test the site:

```zsh
# Build static content
hugo

# Build static content, including draft posts
hugo -D

# Run a local development server
hugo server
```

## Setting Up AWS Resources

### Getting a Domain

The first thing you'll need is a domain for your site and you can buy one from several places - I bought mine from [IONOS](https://www.ionos.co.uk), however you can also [purchase a domain directly through AWS](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html) using Amazon Route 53.

### The Resources

Let's establish the resources we're going to need to deploy.

#### S3 Buckets

We already mentioned that we'll be hosting the site on S3, so we're going to need to two buckets for that, one with the `www` prefix and one without, as well as a bucket to store logs from requests made to our site and a bucket to store build artifacts from the CI/CD pipeline we'll be building.

#### Hosted Zone

A hosted zone is a sub-service of Route 53 that we'll use to determine how requests to our site are routed.

#### Log Group

We'll use a CloudWatch Log Group to store all of the logs from things like our CI/CD pipeline.

#### SSL Certificate

An SSL certificate is a pre-requisite to enforcing HTTPS for all of our web traffic. In essence, when requests are passed to CloudFront, it will pass this SSL certificate to the user's browser so that the browser knows it can trust our website, after which it will initiate a secure connection over SSL. HTTPS is obviously important to have from a security perspective, but it's also worth noting that without it, browsers like Safari or Chrome will show a "Not Secure" flag in the address bar and some anti-virus products may block access to your website unless the user specifically exempts it.

#### CloudFront Distribution

The CloudFront Distribution is the resource we'll use in order to cache our static content, as well as to enforce HTTPS on our site.

#### IAM Roles

We'll need to use several Identity and Access Management (IAM) roles in order to allow various resources to interact with one another and with other AWS services in a secure way, and I'll explain the permissions we're giving each role as we deploy them.

#### CodeBuild Projects and EventBridge Rules

In order to deploy a CI/CD pipeline, we'll also need to use things like AWS CodeBuild projects and Amazon EventBridge rules. Again though, we'll talk about these when we come to building the pipeline. If you don't want a CI/CD pipeline, you can happily ignore these resources and deploy new posts manually - if you do choose to go down that route, you also won't need an S3 bucket store build artifacts.

### Resource Naming Conventions

Throughout the post, I'm going to adopt a fairly standard approach to resource naming which will be as follows:

```zsh
<resource_abbreviation>-<organisation>-<project>-<description>
```

### Pre-Requisite Resources

Before we actually start writing any code, we need to deploy two resources; firstly, a Hosted Zone and secondly, an S3 bucket to hold configuration type data.

Let's start with the Hosted Zone and, again, this needs to be done upfront because my domain is registered outside of AWS, which means once my Hosted Zone is set up, I need to configure the Name Servers for my domain through the IONOS portal. We'll provision a Hosted Zone using the AWS CLI (see the [Getting Started](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) guide if you don't have this set up), and we'll use our base domain for the Hosted Zone name (the caller reference just needs to a unique string, hence why I'm using the current date-time):

```zsh
aws route53 create-hosted-zone \
--name jamiehargreaves.co.uk \
--caller-reference $(echo date)
```

Now that it's set up, we need the Name Server addresses which can then be used to update my IONOS Name Server settings. To do this we need to get the ID of the Hosted Zone we just created (you don't need to use [JQ](https://stedolan.github.io/jq/) here but I like to use it since it formats JSON responses nicely):

```zsh
aws route53 list-hosted-zones | jq
```

This will return an array of Hosted Zones that looks something like:

```json
{
  "HostedZones": [
    {
      "Id": "/hostedzone/Z0827073DSZEQ2F7K5PK",
      "Name": "jamiehargreaves.co.uk.",
      "CallerReference": "terraform-20211230113612691900000001",
      "Config": {
        "Comment": "Managed by Terraform",
        "PrivateZone": false
      },
      "ResourceRecordSetCount": 6
    }
  ]
}
```

We can pull out the Hosted Zone ID in order to take a look at its associated Name Servers:

```zsh
aws route53 get-hosted-zone \
--id /hostedzone/Z0827073DSZEQ2F7K5PK | \
jq '.DelegationSet.NameServers'
```

This returns an array of Name Server addresses:

```json
[
  "ns-1864.awsdns-41.co.uk",
  "ns-9.awsdns-01.com",
  "ns-556.awsdns-05.net",
  "ns-1344.awsdns-40.org"
]
```

The configuration of these will depend on where your domain is registered, so you'll need to look into how to do this for whatever provider you've used. If your domain is registered through Route 53, then a Hosted Zone will already have been created and configured for you as part of the registration process.

Next we'll deploy the S3 bucket (again using the CLI); since we're using it for configuration data - specifically, to store our Terraform state which I'll discuss later - I'm going to make the bucket versioned:

```zsh
# Create bucket
aws s3api create-bucket \
--bucket s3-jamie-general-config \
--create-bucket-configuration '{"LocationConstraint": "eu-west-1"}'

# Enable versioning
aws s3api put-bucket-versioning \
--bucket s3-jamie-general-config \
--versioning-configuration '{"Status": "Enabled"}'
```

### Infrastructure as Code

As I mentioned at the start of the post, I'm going to deploy all the resources into AWS using an infrastructure-as-code approach, rather than manually going into the Management Console and deploying the resources. This isn't strictly necessary for a project of this size, but I find it's much cleaner to have all of my resources version controlled as code and much safer if I need to make changes as I'll be able to see the impact of those changes on my resources before I actually deploy them (plus, I think it's a good habit to get into).

I've chosen Terraform to deploy the resources (have a look [here](https://learn.hashicorp.com/collections/terraform/aws-get-started) if you're not familiar), but there's no reason you couldn't use [AWS CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html) for this. In general though, I think CloudFormation is overly verbose and often poorly documented (though that's just my personal opinion). In addition, there are also limitations around deploying resources into different regions within CloudFormation stacks (which can be achieved using [StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)), but then being able to reference the attributes (e.g. the resource ARN), of the resource within that same stack - Terraform doesn't have this limitation.

Now that's out of the way, we can start defining the rest of our resources. I'll do this within a single `main.tf` file within the `infra` folder. We'll start by defining the main AWS provider and a couple of input variables whose values we'll provide when we deploy the resources. We'll also enforce that the `project` reference only use lowercase characters (I think this looks nicer in resource names).

| :exclamation: Important |
|----------------------------------------------------------------------------------|
A really crucial thing to note here is the use of the `backend` block within the top level `terraform` definition. Terraform stores the state of your deployed resources in a configuration file which, by default is stored locally. The problem here is that if anything happens to your state file (e.g. you accidentally delete it), you can end up with orphaned resources that are no longer registered as remote resources with Terraform. Whilst you could version control this file, this risks compromising sensitive data that Terraform may store in plain text in the state file. For this reason, you should always store your state remotely, in this case in a versioned S3 bucket, and this is the purpose of the `backend` block.

```tf
# Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "s3-jamie-general-config"
    key    = "blog/terraform.state"
    region = "eu-west-1"
  }
}

# Input variables
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
```

I alluded earlier to the need to be able to deploy resources into different regions and this is beacuse CloudFront distributions require all SSL certificates to be provisioned in `us-east-1`, therefore I'm going to define two providers: one in my primary region of `eu-west-1` (i.e. Ireland), and another in `us-east-1` (N. Virginia), which I'll use when I'm deploying the SSL certificate and which I'll alias as `useast`. In both, I'm using the `default_tags` argument which lets us define a set of default tags that are applied to any resources using that provider which support tags:

```tf
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
```

Next we need to define our S3 buckets. The primary bucket that will be used to store our web content needs to be publicly accessible, whilst the rest of our buckets should be private. In addition, the diagram I showed earlier had an arrow indicating that the `jamiehargreaves.co.uk` bucket would redirect to the `www.jamiehargreaves.co.uk` bucket and that's exactly the case. When a request is sent to the base domain, the only purpose of its bucket will be to forward on those requests to the prefixed domain bucket, which will actually contain the web content (though this could be the other way around, it doesn't matter). It's also worth noting that the bucket names for the website itself aren't optional, *you must name your bucket the same name as the domain*.

```tf
# S3 buckets
resource "aws_s3_bucket" "primary_bucket" {
  bucket  = "www.jamiehargreaves.co.uk"
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
```

Here, we've assigned our `primary_bucket` an IAM policy stored in the `policies` sub-folder which allows anonymous public read access to all bucket objects (you can read more about policy definitions in the [documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_grammar.html)):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::www.jamiehargreaves.co.uk/*"
        }
    ]
}
```
