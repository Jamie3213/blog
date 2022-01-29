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

Now, I make it no secret that I think crypto currencies possess none of the fundamental characteristics of real currencies and currently serve little purpose beyond acting as speculative (and extremely volatile), investments with no discernable underlying value. That being said, one thing that is very useful about crypto currencies is the wealth of (often free), real-time APIs that exist to stream crypto trading data and we're going to make use of one such API in this post to see how we can build a real-time streaming pipeline in AWS.

## Tiingo API

As I mentioned, there are various APIs that provide crypto data but a particularly good one (and the one we'll use here), is the [Tiingo crypto websocket API](https://api.tiingo.com/documentation/websockets/crypto). This API provides a real-time stream of crypto trades from a number of exchanges. If you're not familar with the difference between an HTTP-based API and a websocket API, then you can read more [here](https://ably.com/topic/websockets-vs-http) but the TLDR version is that a typical REST API is like asking your friend a question and them telling you the answer, whilst a websocket API is more like asking your friend to tell you every single thing that pops into their mind, as soon as it pops into their mind. Tiingo call their websocket API a firehose and that's a fairly good way to think about it; we're going open a persistent connection with the API and the API is going to spray trades at us as they occur.

To use the Tiingo API, you need to sign up and obtain an API auth token that can be used during the subscription process. There are a few different [pricing tiers](https://api.tiingo.com/about/pricing) for the API, but we'll opt for the free plan (obviously), which gives us up to 5 GB of data per month; more than enough to build a pipeline with.

## The Solution

The solution itself is going to be fairly straightforward (and serverless, of course :information_desk_person: :nail_care:), and the diagram below shows what it's going to look like:

!["Solution diagram."](/images/aws_crypto_streaming/solution_diagram.png)

Roughly speaking:

* A containerised Python application connects to the Tiingo API.
* The application acts as a producer for a Kinesis Data Firehose Stream, pushing batches of trade update messages to the Stream.
* When messages arrive at the Stream, they're funneled in their raw format into an Amazon S3 bucket.
* Each new message batch written to S3 invokes a Lambda function which parses the batch and writes the messages to a DynamoDB table.
