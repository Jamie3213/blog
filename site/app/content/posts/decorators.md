+++
author = "Jamie Hargreaves"
title = "Retry Logic With Decorators In Python"
date = "2022-04-05"
description = "Exploring the use of decorators to separate error handling and retry logic from function code."
tags = [
    "python",
    "aws",
    "kinesis",
    "decorator",
    "clean code"
]
+++

!["Header showing an image of a bookshelf"](/images/dynamodb_concurrency/header.jpg)

## Overview

For a long time decorators were an aspect of Python that I looked at with a degree of hesitancy; I never really understood why I would ever need to write my own decorators, not least because I never really understood how they worked. My only exposure to decorators was adding a `@dataclass` decorator to my classes to better model objects in my code or modifying my class methods with `@classmethod` or `@staticmethod`. It wasn't until I started reading more about the concepts of clean code (and design patterns more broadly), that I stumbled upon a natural use for them, so I thought I'd share that use with you.

## Clean Code

A great way to work towards cleaner code is to look for [code smells](https://refactoring.guru/refactoring/smells), i.e. characteristics in our code that hint at refactoring opportunities - one such code smell is long functions or methods. How long is too long? [Dave Farley](https://www.youtube.com/watch?v=5z5eGcmNikQ&t=504s) suggests that after twenty lines or so we should start asking questions (in fact, he says he fails his CI pipelines after 20 lines). The problem with long functions is that the longer a function becomes, the more complex it tends to become and the more likely it becomes that we increase the degree of coupling in an application by binding together unrelated pieces of code. In many cases the complexity of a function is the result of it doing too many things. Another good indication of this are functions which have a large number of input parameters or which have boolean flags which are used to switch between one behaviour or another within the body of the function. If we want our code to be clean, then as [Uncle Bob](http://cleancoder.com/products) says, our functions should do one thing and do it well.

{{< tweet user="unclebobmartin" id="1023192440579215360" >}}

## Decorators

Now, clean code is all well and good and short functions are great, but what does any of this have to do with decorators? Well, before I answer that question, let's start by having a look at how decorators in Python actually work. The crux of a decorator is that at its heart it's simply a function which wraps another function to add some additional behaviour (you can find much more detailed introductions to decorators [here](https://book.pythontips.com/en/latest/decorators.html) and [here](https://realpython.com/primer-on-python-decorators/), for example, as well as a great talk from PyCon 2019 [here](https://www.youtube.com/watch?v=MjHpMCIvwsY&list=WL&index=8)). Let's consider a simple function which takes an input and prints it to the console:

{{< gist Jamie3213 59ffab16fa49d51d95023ec24549caf0 >}}

Now let's imagine that we want to extend this function's behaviour so that we can optionally run it twice. One way to do this would be to add a boolean flag as a parameter and use an if statement:

{{< gist Jamie3213 edc4f5186def8c4eef91a92f72f477bf>}}

Whilst this works, it's certainly not clean and, in fact, we just mentioned how boolean flags are often an indication of code with unclear intent. A better approach would be to define a generic function which takes a function as its input and executes it twice. We can do this since functions in Python are first-class objects, i.e. we can pass them around like variables:

{{< gist Jamie3213 191c878e4eec450dd586214ee4eeb706 >}}

This new function `twice` takes any callable, along with unpacked non-keyword and keyword arguments, and executes it twice. By creating a separate function to handle this additional behaviour we've separated two distinctly different pieces of code - each function is now responsible for doing one thing and we can re-use `twice` with any function, rather than arbitrarily tying it to the behaviour of `say_something`. This is almost a decorator, so now let's re-write it actually be a decorator:

{{< gist Jamie3213 4289ac4747d9f1e07805567d5dc3c78a >}}

We've passed `say_something` as an argument to `twice` which returns the wrapper function defined within it and we've re-assigned `say_something` to the wrapper (again, remembering that functions are first-class objects), which gives us the result we want. Syntactically however, this looks a bit messy, so Python gives us a more aesthetic way to decorate our function:

{{< gist Jamie3213 d9ac063018f8e8fd5c0cb68ca32cad3a >}}

We now understand exactly how a decorator works (turns out it's not that mystical at all). At this point we could say that the concept of the `twice` function is oddly specific and actually what we'd rather have is a decorator that can execute a function `n` times based on an input parameter, so let's do that:

{{< gist Jamie3213 45be205d9a828eed89fbb3a05634e657 >}}

The format of decorators with input parameters is slightly different as we now have a main outer function which wraps our previous decorator. To understand a little more clearly how this actually works, let's to go back to calling the decorator as a function without the `@` syntax:

{{< gist Jamie3213 e615b05ea4b35f2fbd4ea06d33792efb >}}

What actually happens here is that we first call `n_times` which fixes the value for `n` and returns a new function with a fixed value. From here, we now just have a normal decorator, so we pass `say_something` to it and get back the wrapper which can be called as before.

Finally, it's worth noting that if we provide a default argument in the decorator parameters, then in order to apply it with the default value we need to use a slightly more verbose syntax, namely `n_times()` as opposed to `n_times`.

## Retry Logic In Boto3

Hopefully the inner workings of decorators are clearer now, however our examples were fairly esoteric, so let's try and solidify things by looking at a practical example of how we can use a decorator to implement retry logic when writing records to a Kinesis Data Firehose Delivery Stream with Boto3.
