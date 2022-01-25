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
