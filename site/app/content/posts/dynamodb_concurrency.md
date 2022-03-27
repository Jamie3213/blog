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

One of the things I've always found a little frustrating about Amazon's Boto3 Python library is the lack of asynchrony; whilst languages like Java and Node.js are able to utilise genuine (offical), asynchrony, the Python library is completely synchronous for most of its operations. Depending on what you're trying to do with it, that might not be much of a problem but if, for example, you want to write a large number of records to a service like DynamoDB (or maybe read or write lots of files from Amazon S3, or any other I/O heavy activity you can think of), then you're left with two options: either put up with synchronous writes (admittedly, greatly sped up with bathcing, but still...gross), or use a multi-threading approach - either way, you're stuck with the poor man's asyncrony.

The question I want to answer in this blog post then is one that I'd been curious about for a while but could never really be bothered to test (you'll see why soon enough), namely, is there any notable performance gain to be had by ditching Boto3 completely and using the low-level AWS REST APIs along with aiohttp? To answer that, we'll look at the performance of three approaches to writing records to DynamoDB:

* The standard synchronous Boto3 approach
* The multi-threaded Boto3 approach using asyncio
* Genuine asynchrony using the AWS REST API and aiohttp

As ever, you can find all the source code used in this post on [GitHub](https://github.com/Jamie3213/async-dynmodb-python).

## Project Structure

The source code structure for this little project looks like the following:

```zsh
└── src
    ├── app.py
    ├── data
    │   ├── __init__.py
    │   └── helpers.py
    └── dynamodb
        ├── __init__.py
        ├── asynchronous.py
        ├── helpers.py
        ├── synchronous.py
        └── threaded.py
```

In `app.py` we'll have the main code that will run the comparisons between the approaches, then we'll have a data package which will contain a nice helper to generate test data to write to DynamoDB, and finally we'll have a dynamodb package which will contain the functionality to perform the various type of writes we're interested in along with any useful helper functions.

## Data

Okay, before we write anything to DynamoDB, we need something to actually write so let's start by defining the helper function we're going to use to generate our data. We'll use the [Faker](https://faker.readthedocs.io/en/master/) library to do this since it has lots of nice features that will allow us to generate all kinds of dummy data. We're going to generate fake book entries to store in DynamoDB with each book having an Author, Title, Published Date and an ISBN uniquely identifying it (and serving as the partition key for the DynamoDB table). The code to do this is pretty straight-forward:

{{< gist Jamie3213 1ec373f474d45a16f1f82b8fd9b9448f >}}

We have an aptly named little dataclass to hold a given book's data and a function that, given a `Faker`, returns an instance of our `Book` dataclass with some radomly generated attributes.

## Writing Books to DynamoDB

### Synchronous

Let's start with the simplest case, i.e., writing records in a sequential loop with no concurrency to DynamoDB (this will be our benchmark - if we don't beat this, then we've got some explaining to do):

{{< gist Jamie3213 2b4fb74ee56fc2d2bab212980b7959c2 >}}

Our function `write_records` is a simple as it gets; it takes a list of books and the name of a DynamoDB table, then puts each of them to DynamoDB in a for loop (we're not bothering with any error handling or retry logic here). The function it calls, `boto3_put_book_to_dynamodb`, is a helper function that looks like the following:

{{< gist Jamie3213 0851c3ad61dadcb2e229f1d0066f2f03 >}}

This function simply calls the `PutItem` API using Boto3 and formats the attributes we want to write to DynamoDB in the correct way (the client wrapper is a fairly thin abstraction over the actual REST API, which makes things a little easier later on). You'll notice that we've imported some libraries in this helper module, some of these will be used later on (the fact we've imported the hashlib and hmac libraries gives you an indication of the slog we're in for later).

It's worth noting here that we don't insantiate a new Boto3 client every time we write a record, we instantiate a single client outside of the loop and re-use it in each API call - we could instantiate a new client each time but it would be a complete waste and would massively slow down what is (spoiler) already a slow process to begin with.

### Multi-Threaded

Okay, we can write records one-at-a-time in a loop, so now let's actually write an approach that uses concurrency. The key thing here is that no matter what kind of pretty wrapper we put around it or how many times we add `async` before a function definition, Boto3 will still be blocking, i.e., it'll make a call to the DynamoDB REST API, wait for a response and block anything else from happening until it gets one.

Whilst what we're going to do here isn't asynchronous, we are going to make use of the fact that the asyncio library gives us a neat way to make use of multi-threading in a way that's consistent with how we'd write code involving non-blocking functions (but again, don't be decieved). We'll make use of our existing `boto3_put_book_to_dynamodb` function since nothing is changing there, so we just need a multi-threading wrapper around it:

{{< gist Jamie3213 63384bd1e7cd4f211fe8523c38c13520 >}}

Just like before, we get a list of books to write and the name of the table to write them to. Within the function we get hold of the currently running event loop, then for each of the books, we create a future by calling the loop's `run_in_executor` method and passing in our blocking function and its input parameters (you can read all about the [event loop](https://docs.python.org/3/library/asyncio-eventloop.html) and [futures](https://docs.python.org/3/library/asyncio-future.html#future-object) in the documentation). Essentially, this method handles the orchestration of the various threads that need to be created to run our jobs. The first argument of the `run_in_executor` method is the executor itself which, in this instance, is `None` meaning Python will use the default executor (i.e., use threads). If  we want more control of the specific number of threads, we can pass in an instance of `ThreadPoolExecutor` from the `concurrent.futures` library and manually set the `max_workers` attribute - note though that increasing the max number of threads doesn't necessarily mean that number of threads will be utilised. It's also worth noting that the executor argument has the abstract type of `concurrent.futures.Executor`, so for a CPU-bound task we can also pass in an instance of `ProcessPoolExecutor` to use processes instead of threads.

Finally, we use asyncio's `gather` function with the unpacked list of futures and await the result - if everything goes according to plan, `gather` returns a list of results (if any), from each of the futures.
