+++
author = "Jamie Hargreaves"
title = "Crypto Streaming with AWS"
date = "2022-01-24"
description = "Real-time cryto price streaming and dashboarding."
tags = [
    "aws",
    "fargate",
    "kinesis",
    "s3",
    "lambda",
    "ecs",
    "ecr",
    "crypto"
]
+++

!["Header showing an image of a bookshelf"](/images/aws_crypto_streaming/header.jpg)

## Overview

Now, I make it no secret that I think crypto currencies possess none of the fundamental characteristics of real currencies and currently serve little purpose beyond acting as speculative (and extremely volatile), investments with no discernable underlying value. That being said, one thing that is very useful about crypto currencies is the wealth of (often free), real-time APIs that exist to stream crypto trading data and we're going to make use of one such API in this post to see how we can build a streaming pipeline in AWS.

## Tiingo API

As I mentioned, there are various APIs that provide crypto data but a particularly good one (and the one we'll use here), is the [Tiingo crypto websocket API](https://api.tiingo.com/documentation/websockets/crypto). This API provides a real-time stream of crypto trades from a number of exchanges. If you're not familar with the difference between a traditional REST API and a websocket API, then you can read more [here](https://ably.com/topic/websockets-vs-http). For the TLDR version, a REST API is a bit like asking someone a question and them telling you the answer, whilst a websocket API is more like giving someone permission to tell you every single thing that pops into their mind, as soon as it pops into their mind. Tiingo call their websocket API a firehose and that's a fairly good way to think about it; we're going open a persistent connection with the API and the API is going to funnel trades to us as they occur.

To use the Tiingo API, you need to sign up and obtain an API auth token that can be used during the subscription process. There are a few different [pricing tiers](https://api.tiingo.com/about/pricing) for the API, but we'll opt for the free plan (obviously), which gives us up to 5 GB of data per month; more than enough to build a pipeline with.

## The Solution

The solution itself is going to be fairly straightforward (and serverless, of course :information_desk_person: :nail_care:), and the diagram below shows what it's going to look like:

!["Solution diagram."](/images/aws_crypto_streaming/solution_diagram.png)

Roughly speaking:

* A containerised Python application connects to the Tiingo API.
* The application acts as a producer for a Kinesis Data Firehose Delivery Stream, pushing compressed batches of trade update messages to the Stream.
* When batches arrive at the Stream, they're periodically funneled in their raw format into an Amazon S3 bucket.
* Each new batch written to S3 invokes a Lambda function which parses the batch and writes the messages to a DynamoDB table.

## Firehose vs Data Stream

Before we continue, one thing worth quickly talking about is the difference between Amazon Kinesis Data Firehose and Amazon Kinesis Data Streams. The long and short of it is that Kinesis Data Firehose is essentially a serverless, (near) real-time streaming service, whilst Kinesis Data Streams provides genuine real-time streaming, along with the requirement for a lot more low-level management of the underlying infrastructure and no auto-scaling.

As we'll see below, one of the key decisions we have to make when configuring a Kinesis Data Firehose Delivery Stream is the buffer which is either a value in MiB or a time interval. The key thing here is that the lowest time interval available is 60 seconds, which means unless we have extremely high volumes of throughput into the stream, the data will only be written into S3 every 60 seconds, hence why Kinesis Data Firehose is actually *near* real-time.

For this blog, I don't think 60 seconds is a problem (and in a lot of typical use cases, it's probably not a problem either), but if for example we were looking at building an extremely high-throughput, real-time (i.e. ultra-low latency), streaming application, we'd probably be better off opting for Kinesis Data Streams. In addition, we'd also (probably), be better off choosing a language like Java for the application as opposed to Python, since we could make use of the official [Kinesis Producer Library](https://docs.aws.amazon.com/streams/latest/dev/developing-producers-with-kpl.html) which is specifically for Java which makes it much easier to create high-performance streaming applications.

## Project Structure

We'll use the following folder structure for this project:

```zsh
├── infra
│   └── policies
├── lambda
└── producer
    ├── app
    └── tests
```

* The `infra` folder will contain our Terraform definitions, whilst the `policies` sub-folder will contain IAM policy JSON documents that are referenced in our Terraform code.
* The `lambda` folder will contain the source code for the Lambda Function that will parse our data and write it to DynamoDB.
* The `producer` folder will contain the source code for the Python application that will act as our data producer. The `app` sub-folder contains the source code itself, whilst the `tests` sub-folder will contain unit tests. I won't go over the unit tests in this article, but in general, you should always aim to write them.

The full source code for the blog can be found on [GitHub](https://github.com/Jamie3213/aws-crypto-streaming).

## Resource Naming Conventions

As I've mentioned in other posts, I generally like to stick to a consistent naming convention for my resources:

```zsh
<resource_abbreviation>-<organisation>-<project>-<description>
```

## Base Infrastructure

The first thing we need to do to get started is to deploy our base infrasructure, namely:

* A CloudWatch Log Group for the project.
* An Elastic Container Registry (ECR) repository and associated life-cycle policies.
* A Kinesis Data Firehose Delivery Stream.
* An S3 bucket to store data.
* Associated IAM roles and policies.

As always, I'm going to deploy all of these resources using Terraform, rather than wading through the AWS Management Console (though you're welcome to use the console if you prefer). Note that in this section, we're working inside the `infra` folder of the project and all of our Terraform code will live in `main.tf`.

First, we need to define the core `terraform` block and in here we'll also specify that we're using Amazon S3 as a back-end. The purpose of this is to use a versioned S3 bucket as the storage location for our Terraform state file in order to limt the risk that we somehow detatch our resources from being tracked by Terraform (e.g. by accidentally deleting the state file).

{{< gist Jamie3213 3fd8f0f52f32bf44ac962ab60167f629 >}}

Note that I already have an existing S3 bucket that I use to store project config files like this, however if I didn't I could create one using the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html) as follows:

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

Next, we need to set up some input variables that we'll provide at deployment time:

{{< gist Jamie3213 d212103816f1edb6a5b22feeaab814b4 >}}

Note that I have a variable here called `data_lake` which, as the description suggests, is the name of the S3 bucket which serves as the data lake where we'll store our streaming data. The rationale here is that if you were an organisation, you'd already have a data lake to stream your data into, so I'm referencing it rather than creating it as part of the Terraform script. If you don't have one, create one with the same approach as the config bucket earlier (though you don't need to turn on versioning unless you really want to).

Next is the actual AWS provider - I'm using `eu-west-1` (i.e. Ireland) as my default region, but obviously set this to whatever the appropriate region is for you (you can see all available regions [here](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html)):

{{< gist Jamie3213 7c9ac9bd4cbedb60f0ac83f0f96281cc >}}

The last thing we need before we define any actual resources is a few data sources:

{{< gist Jamie3213 12be7b0ba6d48492e2fb8962ec0f4e83 >}}

These refernce the current AWS region, the identity of the account used to deploy the resources and the data lake bucket we mentioned earlier.

Now for the actual resources, the first of which is a CloudWatch Log Group where we'll store our project logs:

{{< gist Jamie3213 1fb94b22af1305932d69f0d6b43f065f >}}

Next is an Elastic Container Service (ECS) Fargate cluster which is where we'll eventually deploy our Kinesis producer:

{{< gist Jamie3213 aa420d93a3fed2d3910b14d0887b4ddc >}}

Since we're deploying our producer application as a container, we need an ECR repo to hold the Docker image. As well as the repo itself, we'll also deploy a lifecycle policy that will remove any untagged Docker images after 24 hours:

{{< gist Jamie3213 7130275975257f7fc77e1d4f31a68c05 >}}

We now just need the last few resources for the Kinesis Stream itself, the first of which is an IAM policy that the Delivery Stream will assume:

{{< gist Jamie3213 5cce839ecd307bd227da0a722e2d87ff >}}

Note that we're referncing a JSON policy document store in the `policies` sub-folder which looks like this:

{{< gist Jamie3213 3673253f76cfcaad44332176c5e4ad7b >}}

This simply allows Kinesis Data Firehose to assume the role. The second thing we need is a set of policies to associate with the new role:

{{< gist Jamie3213 cf17d76842e8c2f562b2106135460a70 >}}

This looks a bit complicated but is essentially doing two things:

* Giving Kinesis permission to create Log Streams within the Log Group we defined earlier, as well as permission to actually write logs to it.
* Giving some basic S3 write and list permissions to Kinesis on the data lake bucket and any objects conatined within it.

Finally, we just need to define the Delivery Stream to which we'll write records:

{{< gist Jamie3213 b12c9d1b6f5a2a746d92850e82f92315 >}}

The key things to note here are:

* The buffer interval is set to the minimum time value of 60 seconds and the buffer size is 5 MiB. This means that data will be written from the Delivery Stream to S3 either every 60 seconds or every time 5 MiB of new data is written (whichever happens first).
* We're specifying no compression on the data that's written to S3 - that might seem counter-intuitive, but I'll explain why I'm doing that when we come to writing the producer a little later.
* All data is getting written in the "bronze" zone of the data lake - this is a concept that's used a lot when working with [Delta Lake](https://databricks.com/blog/2019/08/14/productionizing-machine-learning-with-delta-lake.html) where we introduce the idea of bronze, silver and gold areas of the lake, with each containing increasingly cleansed, augmented or aggregated data.

Now that we have all of our resources defined, we can deploy them from the Terraform CLI:

```zsh
# Deploy resources
terraform init

terraform apply \
-var project=crypto \
-var created_by=jamie \
-var data_lake=s3-jamie-general-data-lake \
-auto-approve
```

## Data Producer

Now that we have our base infrastructure deployed, we can start to write the producer application and that will consist of a few pieces: we'll need to write the actual Python application, we'll need to write the Dockerfile that will be used to containerise it and we'll need to write some more Terraform to deploy it to AWS.

Before we do any of that however, one thing we need to do is obtain the API auth token that will be used in the application. I mentioned at the start of the article how to [sign up to the Tiingo API](https://api.tiingo.com), so once you do that you'll be provided with the token. From here, we need to add the token to the AWS Secrets Manager so it's stored securely (no storing secrets in plain-text files or, even worse, in the code itself :mask:). To create a new secret we can use the AWS CLI:

```zsh
aws secretsmanager create-secret \
--name TiingoApiToken \
--secret-string <your_token_here> 
```

### Helper Code

For the remainder of this section we're going to be working within the `producer/app` folder. There are also a few things to specify up front:

* I'm going to make extensive use of type hints - you can read all about these in [PEP 484](https://www.python.org/dev/peps/pep-0484/).
* I'm using [Mypy](https://mypy.readthedocs.io/en/stable/) to enforce type checking as I develop the application.
* All our code is going to be formatted using [black](https://black.readthedocs.io/en/stable/), an opinionated code formatting tool.
* All of our imports will be sorted using the [isort](https://pycqa.github.io/isort/) library.

#### Logging Module

Okay, so where do we begin? Well, firstly we need decent logging in our application (no, printing doesn't count as decent logging), so we're going to define a function which will create a named logger - we'll keep this in it's own little module called `logger.py`:

{{< gist Jamie3213 a99577c4148878cdc420ca58866dc4e2 >}}

The logger this function creates will produce logs in a nice format like so:

```zsh
2022-01-22 00:00:00,000 - my_logger_name - INFO - Details of some log event.
```

That's it for logging, though it's worth noting that even though we're just logging to the console, when we deploy this application as a containerised application on Fargate, those logs will automatically be directed to the project's Log Group in CloudWatch - we don't need to do anything special for AWS to capture the logs.

#### AWS Helpers

Next, we'll define a couple of helper functions that we'll use in the applciation; one that let's us retrieve an AWS Secrets Manager secret and another that writes a record to a Kinesis Data Firehose Delivery Stream. We'll store both of these in a new module called `aws_helpers.py`:

{{< gist Jamie3213 3c8ea14c98c145c7939812ee9c38398f >}}

Note (and we'll use this convention throughout), that `_put_record_to_kinesis_stream` is prefixed by an underscore to indicate that the function is internal and shouldn't form part of the public API, i.e. that it's not something that the main client code (`app.py`) will make use of, whereas `get_secrets_manager_secret` is something we're expecting the client code to use.

### Tiingo Module

#### Dependencies

We're now going to be working inside a module called `tiingo.py` for a while which will contain all the logic needed tomget data from the API, maniupalting it and writing it to AWS. To do this, we'll need a number of dependencies:

{{< gist Jamie3213 ed90ca25e723739339d0b1f31dd7c6de >}}

There are three non-standard libraries here:

* First is Botocore which is installed as part of the Boto3 library which is the offical [AWS Python SDK](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/quickstart.html) and which provides the core functionality of Boto3.
* Second is [pydantic](https://pydantic-docs.helpmanual.io) which, among other things, provides a dataclass implementation with enhanced data validation functionality (as we'll see later).
* Finally is the [websocket-client](https://websocket-client.readthedocs.io/en/latest/) package which we'll use to connect to the Tiingo websocket API.

We're also importing the `_put_record_to_kinesis_stream` function that we defined in the AWS helpers earlier.

#### Custom Exceptions

We'll start the actual module by defining a couple of custom exceptions - there's nothing special about these, we're just going to use them to be able to provide more informative exceptions, rather than throwing some built-in exception:

{{< gist Jamie3213 466b1ba58fef63bcef35a5a9f4befc2c >}}

Note that since we call the `__init__` method for each of the classes, we can use `super` to pass in a pre-defined error message to the base exception class, rather than having to write it out everytime we throw the error.

#### API Data Structures

We're now going to start writing the core functionality of the module and when thinking about where to start with that, to me it makes most sense to begin with the data that we'll receive from the API; after all, it's the data we're actually interested in, everything else is just facilitating us moving or manipulating the data.

For the moment, we'll forget about the process of subcribing to the API and think about the kinds of messages the API sends after subscribing. From the [documentation](https://api.tiingo.com/documentation/websockets/crypto) (and from having played around with the API beforehand since the documentation can be a little patchy), we discover that we can ultimately receive four kinds of messages from the API:

* An error message
* A heartbeat message
* A subscription message
* A trade update message

Before we run off defining new classes to hold the messages, let's see what they look like:

```json
# Error
{
    "response": {
        "code": 401, 
        "message": "authorization failed"
    }, 
    "messageType": "E"
}

# Heartbeat
{
    "response": {
        "code": 200,
        "message": "HeartBeat"
    },
    "messageType": "H"
}

# Subscription
{
    "response": {
        "code": 200,
        "message": "Success"
    },
    "messageType": "I",
    "data": {
        "subscriptionId": 4943355
    }
}

# Trade update
{
    "data": [
        "T",
        "lunabusd",
        "2022-02-26T12:48:55.326000+00:00",
        "binance",
        20.0,
        74.99
    ],
    "messageType": "A",
    "service": "crypto_data"
}
```

It's worth noting that each of the messages has a `messageType` parameter that we'll use later when we're parsing them. Also, note the `data` array contained in the trade update message which has the following schema (from the [docs](https://api.tiingo.com/documentation/websockets/crypto)):

* Index: 0 - for trade updates, this is always "T".
* Index: 1 - ticker related to the asset.
* Index: 2 - a string representing the datetime this trade quote came in.
* Index: 3 - the exchange the trade was done on.
* Index: 4 - the amount of crypto volume done at the last price in the base currency.
* Index: 5 - the last price the last trade was executed at.

Okay, we now know the structure of the messages so we'll use dataclasses to represent the different types (you can read about them in the [pydantic docs](https://pydantic-docs.helpmanual.io/usage/dataclasses/)). Since all the messages are ultimately still API messages, it makes sense to define a base parent class that each of the subclasses can inherit from. This seems a bit unnecessary at first because, as we'll see, the super class is empty, but its purpose will become a bit more obvious later:

{{< gist Jamie3213 ddce3705240008f6e8a14d92dbd3ddd0 >}}

We've marked all of these dataclasses as private (i.e., prefixed them with an underscore) since the main application code will never need to actually interact with them. The final dataclass we need is for trade update messages:

{{< gist Jamie3213 c7d2387c1a811cfc78bc3a13ca35540b >}}

Now, the first thing to note is that we've gotten rid of some of the information contained in the API message; we've ignored the `service` value since that will always be "crypto_data" and we've also ignored the first index of the `data` array since this will always have a value of "T".

The second thing to note is the `_ensure_timestamp` method and the use of the `@validator` decorator; this is one of the really useful features that we get from using a pydantic dataclass rather than a vanilla dataclass. The role of the `@validator` is to define a function which is used to validate the specified class attributes upon instantiation, in this case the values of `date` and `processed_at`. The validator checks that these values have the correct format and, if not, tries to correct them (the docstring explains the actual point of this).

#### Parsing Messages

We have the data structures to hold API messages, so now we need a way to actually get the API data *into* those structures. At this point, recall that we can't know upfront what kind of message the API will return, so we can't just say "give me the next trade" and shove that response into the `TradeMessage` class because occassionally when we ask for a trade, we'll actually get a heartbeat message back. This makes things a bit more tricky but the [Gang Of Four](https://en.wikipedia.org/wiki/Design_Patterns) come to the rescue in the form of the [Factory Method](https://en.wikipedia.org/wiki/Factory_method_pattern) design pattern.

The idea of the Factory Method is that we define a bunch of functions which can each parse a certain kind of API message, then define a "factory" function to whom we delegate the responsibility of determining which parser to use based on the `messageType` value. This way, we don't need to worry about specifying the kind of message we need to parse, we just throw our message to the factory and the it figures out the correct parser for us.

The Factory Method pattern makes our code more flexible: if in the future the structure of the messages changes, we don't need to start altering all of our application code, we just add a new parser and update the factory, protetcing the public API from ever knowing anything changed. Since we're using Python as opposed to something like Java (where everything needs to be in a class), we're just using free, module-level functions instead of defining a base parser class and overriding a parse method in different subclasses - there's nothing to stop us doing that but we don't gain anything useful from it and I think this way is more Pythonic.

Now that I've rambled about Factory Methods, let's actually write the code. Firstly, we'll define an enumerator for the different message types (I think this makes things a bit more readable than just using strings), as well as defining a function which maps message types to enums:

{{< gist Jamie3213 4aaf23ac05f4c58c9b98534fe383551d >}}

From here, we can define each of our parsers, one for each of the message types. These are all fairly straight-forward and take a serialized message (i.e., a dictionary), and pull out relevant values to slot into the associated dataclass:

{{< gist Jamie3213 235803309488f96b04e86efbe966b02b >}}

Finally, we just need to define the factory:

{{< gist Jamie3213 141ef9f2475a0f369fb07267c0872b26 >}}

Note that the factory doesn't actually parse anything, it just gives us the correct parser to use which is why we need to use the `Callable` type in the function signature which indicates that we return a function which takes an argument of type `Dict[str, Any]` and returns an object of type `_Message`. *This* is the main reason we chose to have all of our message dataclasses inherit from a base class, otherwise we would've needed to have our function siganture reference something like:

```python
Callable[[Dict[str, Any]], _ErrorMessage | _HeartbeatMessage | _SubscriptionMessage | TradeMessage]
```

This is both ugly (the syntax is bad enough on its own) and inflexible, since we'd need to update this everytime we wanted to add in a new parser.

#### Writing Messages

We can now parse messages and store them in sensible classes, so we need a way to write them to an output (in this case, a Firehose Delivery Stream). We're going to use the same Factory Method approach as above here in order to keep our code flexible. By using a factory, we'll be able to more easily update our code in the future if, for example, we decide we're moving to Azure - all we'd need to do is add functionality to write a record to the necessary Azure output (e.g., EventHubs) and update the factory without needing to change anything else.
