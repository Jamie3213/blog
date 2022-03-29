+++
author = "Jamie Hargreaves"
title = "DynamoDB Write Concurrency In Python"
date = "2022-03-28"
description = "Exploring synchronous and asynchronous writes to DynamoDB in Python."
tags = [
    "aws",
    "dynamodb",
    "python",
    "async"
]
+++

!["Header showing an image of a bookshelf"](/images/dynamodb_concurrency/header.jpg)

## Overview

One of the things I've always found a little frustrating about Amazon's [Boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/quickstart.html) library is the lack of asynchrony. Whilst languages like Java and Node.js are able to utilise genuine (official), asynchrony, the Python library is completely synchronous for most of its operations. Depending on what you're trying to do with it, that might not be much of a problem but if, for example, you want to write a large number of records to a service like DynamoDB (or maybe read or write lots of files with Amazon S3, or any other I/O heavy activity you can think of), then you're left with two options: either put up with synchronous writes (admittedly, greatly sped up with batching, but still...gross), or use a multi-threading approach - either way, you're stuck with the poor man's asynchrony.

The question I want to answer in this blog post then is one that I'd been curious about for a while but could never really be bothered to test (you'll see why soon enough), namely, is there any notable performance gain to be had by ditching Boto3 completely and using the low-level AWS REST APIs along with aiohttp? To answer that, we'll look at the performance of three approaches to writing records to DynamoDB:

* The standard sequential Boto3 approach
* The multi-threaded Boto3 approach using asyncio
* Genuine asynchrony using the AWS REST APIs and asyncio/aiohttp

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

In `app.py` we'll have the main code to run the comparisons between the approaches, then we'll have a data package which will contain a nice helper to generate test data to write to DynamoDB, along with a dynamodb package which will contain the functionality to perform the various type of writes we're interested and some useful helper functions.

## Data

Before we write anything to DynamoDB, we need something to actually write so let's start by defining the helper function we're going to use to generate our data. We'll use the [Faker](https://faker.readthedocs.io/en/master/) library to do this since it has lots of nice features that will allow us to generate all kinds of dummy data. We're going to generate fake book entries to store in DynamoDB with each book having an Author, Title, Published Date and an ISBN uniquely identifying it (and serving as the partition key for the DynamoDB table). The code to do this is pretty straight-forward:

{{< gist Jamie3213 1ec373f474d45a16f1f82b8fd9b9448f >}}

Here we have a little dataclass to hold a given book's data and a function that, given a `Faker` instance, returns an instance of our `Book` dataclass with some randomly generated attributes.

## Writing Books to DynamoDB

### Synchronous

Let's start with the simplest case, i.e., writing records in a sequential loop to DynamoDB with no concurrency (this will be our benchmark - if we don't beat this, then we've done something wrong):

{{< gist Jamie3213 2b4fb74ee56fc2d2bab212980b7959c2 >}}

Our `write_records` function is a simple as it gets; it takes a list of books and the name of a DynamoDB table, then puts each book to the table in a loop (we're not bothering with any error handling or retry logic here). The function implementing the core functionality, `boto3_put_book_to_dynamodb`, is a helper function that looks like the following:

{{< gist Jamie3213 0851c3ad61dadcb2e229f1d0066f2f03 >}}

This function simply calls the `PutItem` API using Boto3 and formats the attributes we want to write in the correct way. The client wrapper is a fairly thin abstraction over the actual REST API which makes things a little easier later on.

You'll notice that we've imported several libraries in this helper module, some of which are used in this function and some of which will be used later on - the fact we've imported the hashlib and hmac libraries gives you an indication of the slog we're in for later.

It's worth noting here that we don't instantiate a new Boto3 client every time we write a record, we instantiate a single client outside of the loop and re-use it in each API call - there's nothing to stop us from instantiating a new client each time but it would be a complete waste and would definitely slow down what is (spoiler) already a slow process to begin with, significantly.

### Multi-Threaded

We can now write records one-at-a-time in a loop, so next let's write an approach that uses concurrency. The key thing here is that no matter what kind of pretty wrapper we put around a function or how many times we add `async` before its definition, Boto3 will still be blocking, i.e., it'll make a call to the DynamoDB REST API, wait for a response and block anything else from happening until it gets one.

Whilst what we're going to do here isn't *truly* asynchronous (or more accurately it's not non-blocking), we are going to make use of the fact that the asyncio library gives us a neat way to make use of multi-threading in a way that's consistent with how we'd write code involving non-blocking functions (but again, don't be deceived). We'll make use of our existing `boto3_put_book_to_dynamodb` helper since nothing is changing there, so we just need to add a multi-threading wrapper around it:

{{< gist Jamie3213 63384bd1e7cd4f211fe8523c38c13520 >}}

Just like before, we get a list of books to write and the name of the table to write them to. Within the function we get hold of the currently running event loop, then for each of the books we create a future by calling the loop's `run_in_executor` method and passing in our blocking function and its input parameters (you can read all about the [event loop](https://docs.python.org/3/library/asyncio-eventloop.html) and [futures](https://docs.python.org/3/library/asyncio-future.html#future-object) in the documentation).

The `run_in_executor` method handles the orchestration of the various threads that need to be created to run our jobs. The first argument is the executor itself which, in this instance, is `None` meaning Python will use the default executor (i.e., use threads rather than processes). If  we want more control over the size of the thread pool, we can pass in an instance of `concurrent.futures.ThreadPoolExecutor` and manually set the `max_workers` attribute, though note though that increasing the max number of threads doesn't necessarily mean that number of threads will be utilised. By default, if no pool size is specified (e.g., when we don't provide an explicit executor), then the size of the thread pool will be set to `min(32, os.cpu_count() + 4)`. This is worth bearing in mind since testing on a high-performance local machine with many cores will yield very different results than running the same code on, for example, a single core Fargate container.

Finally, we use asyncio's `gather` function with the unpacked list of futures and await the result - if everything goes according to plan, this returns a list of results (if any), from each of the futures.

### Asynchronous

We can now write records synchronously in a loop and concurrently using multiple threads, so the final piece of code we need to write is one that uses genuine non-blocking API calls in a single thread. To do that we'll utilise the low-level DynamoDB REST APIs along with the [aiohttp](https://docs.aiohttp.org/en/stable/) library which is essentially the async equivalent to the requests library that would normally be used to make REST API calls in Python.

Now, the aiohttp API is broadly the same as that of the requests library, so why do I keep implying that this method will be such a chore? The answer is that whilst *calling* the APIs in a non-blocking way is easy, constructing the headers for the calls is very convoluted. In AWS's defense, there are hints like the below image in all of their (very limited) documentation of the low-level APIs suggesting that you should probably just stick with the official SDKs instead of hacking together the headers yourself unless you have a very good reason not to:

!["AWS warning that you should stick to the SDKs"](/images/dynamodb_concurrency/aws_warning.png)

Alas, we're going to ignore the suggestion. Any calls made to low-level AWS REST APIs need to use what AWS calls the [*signature version 4 signing process*](https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html) which is essentially a very specific set of information, formatted in a very specific way that's passed along with every request. AWS [describe the process](https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html) like this:

* Step 1: [create a canonical request](https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html)
* Step 2: [create a string to sign](https://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html)
* Step 3: [calculate the signature](https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html)
* Step 4: [add the signature to the HTTP request](https://docs.aws.amazon.com/general/latest/gr/sigv4-add-signature-to-request.html)

The point of all of this is primarily around security, we include a bunch information in the the signature for a given API request (which includes things like hashes of our AWS access key ID and secret access key, timestamps and payload hashes), and AWS recalculate the signature upon receiving the request and check that the two match. This is useful because if, for example, our payload was somehow altered in transit, the signatures would no longer match and, since we include a timestamp, even if someone got hold of a part of the signature, it would only be valid in a small window since the initial request was made.

Now, that's all well and good but it's still incredibly ugly and confusing to implement. Luckily, AWS provide some example code for a number of languages including Java, JavaScript, Ruby, C# and, thankfully, [Python](https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html). As such, I can't take much credit for any of the actual code below beyond cleaning it up and making it a bit clearer what each piece does:

{{< gist Jamie3213 49e77a1015badb89029afaeb510cf06d >}}

Now that we can sign our API requests, we can write a function to make asynchronous calls equivalent to the functionality of the `boto3_put_book_to_dynamodb` helper we used in the synchronous and multi-threaded cases:

{{< gist Jamie3213 f56e1f3409183ec986efe42be30e67c5 >}}

All we're doing here is creating the JSON payload to send to the API (as I mentioned earlier, the Boto3 client wrapper is a very thin abstraction so the payload structure is almost identical to the structure the client expected in the Boto3 cases), as well as defining some extra bits of information like the API endpoint we're going to call and passing all of that information into our helper to produce the request headers including the necessary API signature.

Finally, we need an equivalent `write_records` function to orchestrate writing all of our books to DynamoDB using this new helper:

{{< gist Jamie3213 b608c063af9cee3958d300d4049dde54 >}}

Note that the use of Boto3 here is purely as a convenient means to pull the AWS access key ID, secret access key and region values without having to rely on environment variables. In addition, analogously to our use of a single Boto3 client earlier, we instantiate the aiohttp client session outside of the loop and re-use it in each call. Again, we could create a new session each time, but all we'd achieve is to slow down the execution of our calls.

Finally, note that the use of `ensure_future` is analogous to the way we used `run_in_executor` in the multi-threaded example, however rather than returning a future, this method returns a [task](https://docs.python.org/3/library/asyncio-task.html#awaitables).

## Comparing Approaches

We now have each of our approaches defined; sequential looping, multi-threading and non-blocking async API calls - time to find out which is faster. We'll do this in the `app.py` file I mentioned at the start:

{{< gist Jamie3213 47730f57f06afa317b0410ce99e773d4 >}}

We've defined three tables, SyncBooks, ThreadedBooks and AsyncBooks (one for each of the approaches), and also set the number of books to generate to 10,000.

Before we run the script, we need to create the three DynamoDB tables and we can do this using the AWS CLI (note that each of these tables will use the on-demand pricing model as opposed to provisioned throughput). The following bash script creates them:

{{< gist Jamie3213 ed4c2c7c35d30c26c2f391e2d82ac9c4 >}}

We can run the script from the terminal:

```zsh
./create_tables.sh
```

With the tables created, we can run our Python script and see how our different approaches stack up against one another:

```zsh
python src/app.py
```

Once the script completes, we get the following results (using [termgraph](https://github.com/mkaz/termgraph)):

```zsh
Synchronous : ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇ 832.65
Threaded    : ▇▇▇▇ 71.23
Asynchronous: ▏ 11.06
```

The first thing that stands out here is that, regardless of which alternative approach you use, the sequential approach sucks. Again, we could obviously improve this significantly by writing records in batches, but then we could also improve the other approaches with batching as well, so the criticism remains.

Secondly, the performance gain we get from the multi-threading approach is huge; we manage an 11.7x boost by using multi-threading so, at a minimum, we should probably at least be considering this approach for any I/O heavy operations like this in AWS (though obviously our mileage will vary by service).

Finally, even compared to the multi-threading approach, using non-blocking API calls still gives a substantial increase in performance again, with a roughly 6.5x boost - when compared to the sequential approach, the non-blocking approach provides a massive 75x increase in throughput.

## Verdict

For me, the key takeaways here are:

* If you're doing I/O intensive operations with AWS services, then you should definitely consider multi-threading to be your default approach. Compared with the simplest, sequential alternative, the performance gain is enormous and the additional implementation effort required is minimal.
* If performance is absolutely critical to you (at least with DynamoDB and, again, it's important not to generalise this to every AWS service), then you can achieve another big performance boost by using the low-level AWS REST APIs with a non-blocking library like aiohttp. The obvious downside with this approach is the increased complexity of the code, though there's an argument that whilst the implementation seems quite complex, we're just implementing a very well-defined set of steps.

The overall conclusion then is potentially quite predictable; sequential writes are slow, threads are faster and true async is faster still but with the trade-off of added complexity due to the lack of async support in the Python SDK. What the correct approach is for you will depend entirely on the use-case and weighing up the trade-offs, but hopefully this post gives some useful insight into the potential options available and their comparative performance.
