+++
author = "Jamie Hargreaves"
title = "DynamoDB Write Concurrency In Python"
date = "2022-03-24"
description = "Exploring synchornous and asynchronous writes to DynamoDB in Python."
tags = [
    "aws",
    "dynamodb",
    "python",
    "async"
]
+++

!["Header showing an image of a bookshelf"](/images/dynamodb_concurrency/header.jpg)

## Overview

In this post we explore concurrency in Python when writing records to Amazon DynamoDB, looking at the two main ways to achieve concurrency (multi-threading with `boto3` and asynchrony with `aiohttp`), comparing how the two approaches stack up against each other, as well as how they compare to a typical synchronous approach.
