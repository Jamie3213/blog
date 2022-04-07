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

For a long time decorators were an aspect of Python that I looked at with a degree of hesitancy; I never really understood why I would ever need to write my own decorators, not least because I never really understood how they worked. My only real exposure to decorators was adding a `@dataclass` decorator to my classes to better model objects in my code or modifying my class methods with `@classmethod` or `@staticmethod`. It wasn't until I started reading more about the concepts of clean code (and design patterns more broadly), that I stumbled upon a natural use for them, so I thought I'd share that use with you.

## Clean Code

A great way to work towards cleaner code is to look for [code smells](https://refactoring.guru/refactoring/smells), i.e. characteristics in our code that hint at refactoring opportunities - one such code smell is long functions or methods. How long is too long? [Dave Farley](https://www.davefarley.net) suggests that after twenty lines or so we should start asking questions, whilst [refactoring.guru](https://refactoring.guru/smells/long-method) recommend we start asking questions after ten lines. The problem with long functions is that the longer a function becomes, the more complex it tends to become. In many cases the complexity of a function is the result of it doing too many things. Another good indication of this are functions which have a large number of input parameters or which have boolean flags which are used to switch between one behaviour or another within the body of the function. If we want our code to be clean, then as [Uncle Bob](http://cleancoder.com/products) says, our functions should do one thing and do it well.

{{< tweet user="unclebobmartin" id="1023192440579215360" >}}

## Decorators

Now, clean code is all well and good and short functions are great, but what does any of this have to do with decorators? Well, before I answer that question, let's start by having a look at how decorators in Python actually work. The crux of a decorator is that at its heart it's simply a function which wraps another function to add some additional behaviour (you can find much more detailed introductions to decorators [here](https://book.pythontips.com/en/latest/decorators.html) and [here](https://realpython.com/primer-on-python-decorators/), for example, as well as [a great talk from PyCon 2019](https://www.youtube.com/watch?v=MjHpMCIvwsY&list=WL&index=8)). Let's consider a simple function which takes an input and prints it to the console:

{{< gist Jamie3213 59ffab16fa49d51d95023ec24549caf0 >}}

Now let's imagine that we want to extend this function's behaviour so that we can optionally run it twice. One way to do this would be to add a boolean flag as a parameter and use an if statement:

{{< gist Jamie3213 edc4f5186def8c4eef91a92f72f477bf>}}

Whilst this works, it's certainly not clean and, in fact, we just mentioned how boolean flags are often an indication of code with unclear intent. A better approach would be to define a generic function which takes a function as its input and executes it twice. We can do this since functions in Python are first-class objects, i.e. we can pass them around like variables:

{{< gist Jamie3213 191c878e4eec450dd586214ee4eeb706 >}}

This new function `twice` takes any callable, along with any non-keyword and keyword arguments, and executes it twice. By creating a separate function to handle this additional behaviour we've separated two distintly different pieces of code - each function is now responsible for doing one thing and we can re-use `twice` with any function, rather than arbitrarily tying it to the behaviour of `say_something`. This is more or less what decorators do, so now let's re-write `twice` to formally turn it into a decorator:

{{< gist Jamie3213 4289ac4747d9f1e07805567d5dc3c78a >}}

We've passed `say_something` as an argument to `twice`, `twice` has returned the `wrapper` function defined within it and we've re-assigned `say_something` to the `wrapper` which gives us the result we want. Syntactically however, this looks a bit messy, so Python gives us a more aesthetic way to decorate our function:

{{< gist Jamie3213 d9ac063018f8e8fd5c0cb68ca32cad3a >}}

Now we understand exactly how a decorator works. We could at this point say that the concept of the `twice` function is a bit too specific and actually what we'd rather have is a decorator that can execute a function `n` times based on an input parameter, so let's do that:
