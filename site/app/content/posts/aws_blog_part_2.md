+++
author = "Jamie Hargreaves"
title = "Blogging with AWS - Part 2: Implementing a CI/CD Pipeline"
date = "2022-01-22"
description = "Building a CI/CD pipeline to deploy changes to a static S3 website."
tags = [
    "aws",
    "amazon s3",
    "aws codebuild",
    "aws lambda",
    "terraform",
    "hugo",
    "ci/cd",
    "monorepo"
]
+++

!["Header showing an image of a bookshelf"](/images/blog_part_2/header.jpg)

## Overview

In [Part 1]({{< ref "aws_blog_part_1.md" >}}) we walked through the process to build and deploy a static website on Amazon S3 using Terraform. At the end of that post, we deployed our content manually to S3 using the `hugo deploy` command and this was very easy to do, enough so that a CI/CD pipeline is probably overkill. Despite this, deploying a CI/CD pipeline is still fun and I think it's a great way to learn how to implement one in AWS if you're not familiar. Also, if you're using a non-Hugo framework that doesn't have such a nice deployment solution, then this might also be useful for you. It's worth saying that whilst I'm building this CI/CD pipeline to deploy a static site, the pattern itself is applicable to any deployment you want to do.

As always, you can find the full source code for my blog in the [GitHub repo](https://github.com/Jamie3213/blog).

## Project Structure

In [Part 1]({{< ref "aws_blog_part_1.md" >}}) we used the following project structure:

```zsh
├── infra
|   └──  policies
└── site
    ├── app
    └── release
```

We'll need to tweak this slightly, so our new project structure is going to look like the below:

```zsh
├── infra
│   ├── lambda
│   └── terraform
|       └── policies
└── site
    ├── app
    └── release
```

All we've done is move our Terraform code into its own folder and add an additional folder which will store the source code for the Lambda function we're going to write (we'll talk about this later).

## The Pipeline

Before we start writing any Terraform, let's look at how the CI/CD pipeline will work. I'm storing all of my source code in GitHub, so what I'd like is for any commits to my `main` branch (generally, a merged Pull Request after I've written a post on a development branch, i.e. [GitHub flow](https://docs.github.com/en/get-started/quickstart/github-flow)), to trigger AWS to build all my static files and deploy them to S3 reliably without me having to do anything.

To achieve this we're going to use the solution described in the below diagram:

!["CI/CD Pipeline Architecture"](/images/blog_part_2/solution_diagram.png)

The description of this pipeline is as follows:

* I make changes to my site (e.g. adding a new blog post), and raise a Pull Request which I merge into the main branch of my GitHub repo.
* The merge triggers a webhook which makes a POST request to the configured callback URL and invokes the CodeBuild project. This CodeBuild project copies the source code from GitHub and executes a series of commands defined in a build instructions file.
* Once the build has completed, the build artifacts are zipped and uploaded to Amazon S3.
* The upload of a new file to the bucket triggers a Lambda function which, in turn, triggers the deployment CodeBuild project.
* This CodeBuild project downloads the build artifacts from Amazon S3, then deploys them, i.e. copies the static content to the primary S3 bucket.

One thing you might ask at this point is why we need to start messing around with custom Lambda functions as opposed to, for example, using something like an event trigger through EventBridge, since EventBridge supports triggering CodeBuild projects from S3 change events. The answer is that I want all of my build artifacts to live in a single S3 bucket, within which I use different folders to separate different projects, for example:

```zsh
s3-jamie-general-release-artifacts/blog/build.zip
s3-jamie-general-release-artifacts/my-other-project/build.zip
```

If we use an S3 change event with EventBridge, we won't be able to include a filter on the object prefix, therefore, our deployment would be triggered every time a new build artifact was added to the bucket, regardless of whether it relates to that deployment project. In addition, if we were using a true monorepo approach in which we needed to trigger different deployments based on which files in the repo were changed (e.g. when files in the `foo/` folder change, we trigger one deployment, but when files in the `bar/` folder change, we trigger a different deployment), then we'd also be out of luck. Hence, we're going to write a Lambda function to do the job for us - luckily, it's a very simple function.

## The Resources

As we did in [Part 1]({{< ref "aws_blog_part_1.md" >}}), let's establish what resources we need to deploy.

### S3 Buckets

We only need to deploy one additional bucket here which we'll use (as highlighted above), to store the build artifacts output from our pipeline.

### Log Group

Log Groups are objects that exist within Amazon CloudWatch; in essence, they're containers into which our resources can write Log Streams and we'll use a Log Group to store the build and deploy logs from our CodeBuild projects.

### IAM Roles

We'll need to deploy some new IAM roles for use with things like CodeBuild and Lambda.

### CodeBuild

CodeBuild is the AWS service we're going to use to do the grunt work in our pipeline. Essentially, CodeBuild lets us provision a container which then automatically runs the commands defined in our buildspec YAML file - we'll use this both for build and deploy.

### Lambda

Lambda is one of the most used services in AWS; it allows us to run code in various languages using a serverless approach, meaning we only pay for the resources the code uses whilst it executes and don't need to worry about provisioning or managing any of the underlying infrastructure.

## Infrastructure-as-Code

Now that we understand what we need to build, let's carry on adding to the Terraform file we started in [Part 1]({{< ref "aws_blog_part_1.md" >}}) - we'll be using the same input parameters etc. so take a look there if you haven't already, or alternatively have a look at the source code in GitHub. We'll start with the S3 bucket that will hold our build artifacts:

```tf
resource "aws_s3_bucket" "release_bucket" {
  bucket = "s3-jamie-general-release-artifacts"
}
```

Next, we'll deploy a Log Group to store our resource logs:

```tf
resource "aws_cloudwatch_log_group" "log_group" {
  name = "/aws/jamie/${var.project}"
}
```

From here, we need an IAM service role that CodeBuild can use when it's building and deploying our resources:

```tf
resource "aws_iam_role" "codebuild_iam_role" {
  name               = "iam-${data.aws_region.current.name}-jamie-${var.project}-codebuild-service-role"
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
      "Sid": "InvalidateCloudFrontPaths",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation"
      ],
      "Resource": "${aws_cloudfront_distribution.distribution.arn}"
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
```

Okay, there's quite a bit going on in this block, so let's walk through it. Firstly, I'm defining an IAM role which is utilisng a policy defined in the `infra/terraform/policies` sub-folder which looks like this:

```json
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

```

This is a standard step where we specify the principal (in this case the AWS service), that can assume this role and therefore carry out the Actions which are defined in the policy (you can read more about how AssumeRole works in the [documentation](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)). The definition of the policy is defined in the `codebuild_iam_policy` resource and it allows the following:

* Creation of Log Streams and the writing of logs to the stream within the Log Group we created for the project.
* Read/write access on the release artifacts and primary web content buckets, as well as any objects stored within them.
* Invalidation of CloudFront distribution paths for the distribution created in [Part 1]({{< ref "aws_blog_part_1.md" >}}).
* Full access to the Key Management Service for use in encrypting and decrypting build artifacts in S3.

With that, we can now define the build project itself:

```tf
# CodeBuild project - build
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
    path      = "blog/"
    packaging = "ZIP"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.log_group.name
      stream_name = "codebuild/build"
    }
  }
}
```

As with the IAM role, there's quite a bit going on here, but the cliff notes are:

* We specify the source to be our GitHub repo, along with the name of the buildspec file (we'll talk about this soon).
* We define the type of container we want to use, in this case a Linux container (CodeBuild uses Ubuntu).
* We provide the path and name of the build artifact that the CodeBuild project produces and indicate that the artifact should be zipped.
* We define where we want our logs to be stored.

It's also worth mentioning the presence of the `badge_enabled` flag; this is completely optional but when enabled, the CodeBuild project will contain a dynamic URL that we can add to our GitHub README file which will show the current status of the build:

!["Build badge example"](/images/blog_part_2/build_badge.png)

I mentioned earlier that when we commit to the GitHub repo, we use a webhook to trigger the build. You can read more about GitHub webhooks [here](https://docs.github.com/en/developers/webhooks-and-events/webhooks/about-webhooks), but in short, when we commit to the repo, GitHub makes an API call which invokes the configured CodeBuild project. The webhook is defined as follows:

```tf
# GitHub webhook
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
```

The webhook is triggered on `PUSH` events to the `main` branch of the repo. Importantly, we're using a `FILE_PATH` filter which means that only changes to files within the `site` folder will trigger the webhook; this is good because if we updated the README or the gitignore file for example, then we wouldn't want our deployment pipeline to be invoked. In addition, the use of these filters also means that we can invoke different build projects depending on the what we change in our commit which allows for the [monorepo](https://www.atlassian.com/git/tutorials/monorepos) approach we're taking here.

Before we define the deployment build project, let's talk about the buildspec. You can read more about it in the [official documentation](https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html), but the buildspec is essentially a YAML configuration file which acts like a shell script and tells CodeBuild what the "build" actually entails, i.e. the commands it should run. Since we're using CodeBuild for both the build *and* deployment, we'll use two different buildspecs; one called `buildspec_build.yml` and another called `buildspec_deploy.yml`, and they'll live in the `site/release` sub-folder. The build buildspec is going to look like this:

```yml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Installing build dependencies...
      - wget https://github.com/gohugoio/hugo/releases/download/v0.91.2/hugo_0.91.2_Linux-64bit.deb
      - dpkg -i hugo_0.91.2_Linux-64bit.deb
      - apt-get -y install
    build:
      commands:
        - echo Build started on `date`
        - echo Building website...
        - cd site/app
        - hugo
artifacts:
  files:
    - site/app/public/**/*
```

All the above commands do is download and install Hugo in the container, build the static content into the `public` folder, and then output the files in that folder as a zipped build artifact to S3.

Next, we can define the deployment build project and this is broadly the same as the previous build project except that we don't need to output any artifacts. In addition, we also make use of `environment_variable` blocks within which we define three environment variables that will be made available to us when we come to run the deployment: the name of the S3 bucket into which our web content should be deployed, the name of the S3 bucket which holds the build artifacts and the ID of our CloudFront distribution which we'll reference when we invalidate the associated CloudFront paths.

```tf
# CodeBuild project - deploy
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

    environment_variable {
      name  = "CLOUDFRONT_ID"
      type  = "PLAINTEXT"
      value = aws_cloudfront_distribution.distribution.id
    }
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.log_group.name
      stream_name = "codebuild/deploy"
    }
  }
}
```

The buildspec for the deployment stage is as follows:

```yml
version: 0.2

phases:
  build:
    commands:
      - echo Deployment started on `date`
      - echo Downloading build artifacts...
      - aws s3 cp s3://$S3_BUILD_BUCKET/blog/build.zip .
      - unzip build.zip -d build
      - echo Deploying build artifacts...
      - aws s3 cp --recursive build/site/app/public s3://$S3_DEPLOY_BUCKET
      - echo Invalidating CloudFront paths...
      - aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*"
```

All the above commands do is download and unzip the build artifacts, recursively write all the files to the S3 deployment bucket and then invalidate any existing files in the CloudFront cache.

At this point all we have left to do is to write our Lambda function and add the relevant resource defintions to the Terraform file.

## Writing the Lambda Function

As mentioned previously, the Lambda function we need will be fairly simple; all it needs to do is start the desired CodeBuild project whenever a new build artifact is written to the `blog` folder of the S3 bucket `s3-jamie-general-release-artifacts`. Let's go through the Lambda code itself which we'll write in Python (see below for the full code):

{{< detail-tag "Full Lambda source code" >}}

```python
import json
import logging
import os

import boto3

from typing import Any, Dict, List, TypedDict

from aws_lambda_powertools.utilities.typing import LambdaContext


# ------------------------------ Define logging ------------------------------ #

logger = logging.getLogger("deploy_trigger")
logger.setLevel(logging.INFO)

# Format output
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")

# Console handler
consoleHandler = logging.StreamHandler()
consoleHandler.setFormatter(formatter)
consoleHandler.setLevel(logging.INFO)

# Add handlers
logger.addHandler(consoleHandler)

# ---------------------------------- Typing ---------------------------------- #

class S3EventNotification(TypedDict):
  Records: List[Dict[str, Any]]

class LambdaResponse(TypedDict):
  isBase64Encoded: bool
  statusCode: int
  body: str

# ---------------------------------- Handler --------------------------------- #

def lambda_handler(event: S3EventNotification, context: LambdaContext) -> LambdaResponse:
  CODEBUILD_PROJECT = os.environ['CODEBUILD_PROJECT']

  logger.info(f"Starting CodeBuild project {CODEBUILD_PROJECT}.")
  codebuild = boto3.client("codebuild")
  build = codebuild.start_build(projectName=CODEBUILD_PROJECT)
  build_status = build['build']['buildStatus']

  if build_status not in ["SUCCEEDED", "IN_PROGRESS"]:
    msg = f"Failed to CodeBuild project '{CODEBUILD_PROJECT}', build status returned '{build_status}'"
    logger.error(msg)
    return LambdaResponse(isBase64Encoded=False, statusCode=500, body=json.dumps(msg))
  else:
    msg = f"Build started and returned status '{build_status}'"
    logger.info(msg)
    return LambdaResponse(isBase64Encoded=False, statusCode=200, body=json.dumps(msg))

```

{{< /detail-tag >}}

Firstly, we need to import a some modules that we'll use in the function; some of these are optional and only imported because I'm using type hints (read more about these in the [docs](https://docs.python.org/3/library/typing.html)):

```python
import json
import logging
import os

import boto3

from typing import Any, Dict, List, TypedDict

from aws_lambda_powertools.utilities.typing import LambdaContext
```

The `boto3` module is the [official AWS Python SDK](https://docs.aws.amazon.com/pythonsdk/), whilst `aws_lambda_powetools` is a nice open-source library that adds support for Lambda typing (among other things) - have a look at [the official site](https://awslabs.github.io/aws-lambda-powertools-python/latest/). Again, the `typing` module is being imported to support type hints.

Secondly, let's define some custom logging - this is optional and in fact you can actually [use the `print` function to do logging from a Lambda function](https://docs.aws.amazon.com/lambda/latest/dg/python-logging.html), however I like to be able to specify the structure of the logs a bit more specifically, so I'll use a more traditional logger:

```python
logger = logging.getLogger("deploy_trigger")
logger.setLevel(logging.INFO)

formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")

consoleHandler = logging.StreamHandler()
consoleHandler.setFormatter(formatter)
consoleHandler.setLevel(logging.INFO)

logger.addHandler(consoleHandler)
```

This will produce log messages that look something like this:

```zsh
2022-01-22 00:00:00,000 - deploy_trigger - INFO - This is a log message
```

Next, let's define some classes which inherit from the `TypedDict` class (you can read about that in the [docs](https://www.python.org/dev/peps/pep-0589/)), which we'll use to define the overall structure of the S3 change event that will trigger the Lambda function (which you can see [here](https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-content-structure.html)), as well as the structure of the response message that the function will return:

```python
class S3EventNotification(TypedDict):
  Records: List[Dict[str, Any]]

class LambdaResponse(TypedDict):
  isBase64Encoded: bool
  statusCode: int
  body: str
```

Now we're ready to define the Lambda handler itself. The first thing it will do is read the value of an environment variable called `CODEBUILD_PROJECT` which will be defined in our Terraform code and will correspond to the name of the CodeBuild project responsible for deploying the static site content. The second thing the function will do is to use the `boto3` library and the `start_build` method to kick off the CodeBuild project:

```python
def lambda_handler(event: S3EventNotification, context: LambdaContext) -> LambdaResponse:
  CODEBUILD_PROJECT = os.environ['CODEBUILD_PROJECT']

  logger.info(f"Starting CodeBuild project {CODEBUILD_PROJECT}.")
  codebuild = boto3.client("codebuild")
  build = codebuild.start_build(projectName=CODEBUILD_PROJECT)
```

The call to `start_build` is asynchronous, so the fact we've called it doesn't actually mean the project has started. However, the response from the method does give the build status at that point which can either be `SUCCEEDED`, `FAILED`, `FAULT`, `TIMED_OUT` or `IN_PROGRESS`, so we'll add a check that the status was either `SUCCEEDED` or `IN_PROGRESS` and if it wasn't, then we'll return an error.

```python
  build_status = build['build']['buildStatus']

  if build_status not in ["SUCCEEDED", "IN_PROGRESS"]:
    msg = f"Failed to start CodeBuild project '{CODEBUILD_PROJECT}', build status returned '{build_status}'"
    logger.error(msg)
    return LambdaResponse(isBase64Encoded=False, statusCode=500, body=json.dumps(msg))
  else:
    msg = f"Build started and returned status '{build_status}'"
    logger.info(msg)
    return LambdaResponse(isBase64Encoded=False, statusCode=200, body=json.dumps(msg))
```

With that, our Lambda function is complete, but we still need to zip it ready for Terraform to deploy. The easiest way to do this is to first create a Python virtual environment to install the project dependencies into (you can read more about virtual environments in the [docs](https://docs.python.org/3/tutorial/venv.html) if you're not familiar), along with a `requirements.txt` file that contains a list of all the required packages. The TLDR version on macOS or Linux is:

```zsh
# Create a new venv
python3 -m venv .venv

# Activate the venv
source .venv/bin/activate

# Install dependencies
pip install boto3 aws_lambda_powertools

# Create a requirements file
pip freeze > infra/lambda/requirements.txt
```

Now that we have our `requirements.txt` file, we need to directly install the same dependencies into the `lambda` folder using the `--target` argument:

```zsh
pip install -r infra/lambda/requirements.txt --target infra/lambda
```

Finally, we need to recursively zip all of the files in the `infra/lambda` folder - note that we need to zip the files *not* the folder:

```zsh
cd infra/lambda
zip -r ../lambda.zip .
```

Now that we've done this, we can finish up and add the remaining pieces of Terraform code.

## Infrastructure-as-Code Continued

The first thing we need for our Lambda function is an IAM role that it can use to perform the required activities:

```tf
# Lamdba IAM role
resource "aws_iam_role" "lambda_iam_role" {
  name               = "iam-${data.aws_region.current.name}-jamie-${var.project}-lambda-trigger-codebuild"
  assume_role_policy = file("policies/lambda_assume_role.json")
}
```

As before, this references a policy in the `policies` sub-folder that allows Lambda to assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Next we associate a set of permissions with the role, namely, the ability to create Log Groups and Log Streams, as well as writing to Log Streams, and the ability to start the `deploy-jamie-blog-site` CodeBuild project:

```tf
# Lambda IAM policy
resource "aws_iam_role_policy" "lambda_iam_policy" {
  name = "policy-jamie-${var.project}-lambda-trigger"
  role = aws_iam_role.lambda_iam_role.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateAndPutLogStreams",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*"
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
```

Annoyingly, one of the limitations of Lambda is that we can't specify the Log Group it writes to, Lambda will create its own Log Group by default, hence why we've also provided permissions for it to create new Log Groups (more on this in the [docs](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs.html)).

Now we can define the Lambda function itself:

```tf
# Lambda function
resource "aws_lambda_function" "codebuild_trigger" {
  filename      = "../lambda.zip"
  function_name = "lambda-jamie-${var.project}-trigger-deployment"
  handler       = "app.lambda_handler"
  role          = aws_iam_role.lambda_iam_role.arn
  runtime       = "python3.9"
  architectures = ["arm64"]
  memory_size   = 128
  description   = "Triggers CodeBuild build project based on S3 change events."
  timeout       = 10

  environment {
    variables = {
      CODEBUILD_PROJECT = aws_codebuild_project.deploy.name
    }
  }

  source_code_hash = filebase64sha256("../lambda.zip")
}
```

Most of this is fairly self-explanatory, but let's point out a few things:

* The `filename` points to the zip file we created earlier, relative to the `main.tf` file.
* I've specified that the Lambda function should run on ARM, since this is cheaper.
* We've defined an environemnt variable called `CODEDBUILD_PROJECT` which takes the value of the deployment project and is the value used in our Python code from earlier.

| :exclamation: Important |
|----------------------------------------------------------------------------------|
The `source_code_hash` is important, if we don't include this then even if we change the Lambda source code in the future, if nothing else changes, then Terraform won't udpate the Lambda function. This way, we hash the zip file which changes the value whenever we change the contents.

We just have two more things to define. We need to give the S3 bucket permission to invoke our Lambda function when a relevant change event occurs:

```tf
# S3 permissions
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.codebuild_trigger.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.release_bucket.arn
}
```

Finally, we need to add an event notification onto the bucket holding the build artifacts:

```tf
# S3 bucket notification
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
```

This needs to be defined with the `depends_on` attribute referencing the permission we just defined since we don't actually reference any the permission anywhere, so we need to manually state the dependency. In addition, we use the `filter_prefix` to make sure the function is only triggere when the blog build artifact changes, and we only trigger on an object creation event.

With that, all of the resources needed for our CI/CD pipeline have been defined and we can deploy the resources:

```zsh
terraform init

terraform apply \
-var project=blog \
-var created_by=jamie \
-auto-approve
```

Now, whenever we add a new blog post and commit it to the `main` branch (or merge a Pull Request into `main`), a webhook will trigger a CodeBuild project to build our static content and write it to an S3 bucket. The act of writing the build artifact to S3 will then trigger our Lambda function which in turn will trigger another CodeBuild project which will grab our build artifacts and deploy them to S3, as well as invalidating any old content cached on CloudFront!
