+++
author = "Jamie Hargreaves"
title = "Pragmatic Functional Programming in Python - Part 1: What Makes Code Functional?"
date = "2023-01-03"
description = ""
tags = [
]
+++

!["Header showing an image of a bookshelf"](/images/dynamodb_concurrency/header.jpg)

## Who cares?

Before we get into any of the details of functional programming (FP), let's clear up the most important question: *who cares?* When I'm writing code, I want it to satisfy two main requirements:

* Easy to read and understand
* Easy to test

If a programming paradigm can't help with these requirements, then I'm not interested. Luckily, I think FP can help achieve both.

That's great, but why *another* blog? The main reason is that I found myself constantly struggling to learn about FP in the context of Python (which is the language I write in day-to-day). The purpose of this blog series then is to frame what I've learnt about FP so far in the context of Python and, hopefully, save other people from the drudgery of having to piece together a convoluted tapestry of blogs, conference talks, books and StackOverflow threads (at least for the basics).

## What is functional programming?

I've decreed that FP can somehow help you write better code, but what exactly makes code functional in the first place? When I started learning about FP, the answer to that question was surprisingly elusive. After a while, I stumbled upon a really nice blog by [Mary Rose Cook](https://maryrosecook.com) called [*An introduction to functional programming*](https://codewords.recurse.com/issues/one/an-introduction-to-functional-programming). In the blog, Mary hits home the fact that functional code is just code without side-effects. This fact is something that's often missing from a lot of explanations of FP. What typically overshadows it is a discussion about writing declarative code. Lots of people will tell you about the benefits of using map, reduce and filter, tail call optimistion, folding, currying and so on. Whilst I'm a massive proponent of writing declarative code, *none of these things inherently make code functional*. I usually think about FP as follows:

> Functional programming is about building functionality through the composition of pure functions.

### Function composition

When we talk about function composition, all we're really talking about is directly passing the return value from one function as the argument to another function without defining any intermediary variables. Let's imagine we have three functions `f`, `g` and `h`, and some variable `x`. If we want to pass the result of evaluating `f(x)` as the argument to `g` and pass that result as the argument to `h`, then we could do that easily:

```python
f_result = f(x)
g_result = g(f_result)
h_result = h(g_result)
```

Alternatively, we could cut out the middle man and do the whole thing in a one-line operation:

```python
h_result = h(g(f(x)))
```

This exactly what we're thinking of when we talk about function composition. The obvious downside here is that this is really ugly, especially with more functions (all of which have proper names), so later in the series we'll look at more aesthetic (and practical) ways to perform this kind of operation.

### Functional purity

Okay, so we understand the first part of the FP definition, but we still have the second part: what exactly is a pure function? A pure function is any function which:

* Is referentially transparent, and
* Has no side effects

Both of these things are very "FP buzzword" and their meanings aren't particularly obvious but they're both terms that get thrown around a lot. Simply, a function is referentially transparent if replacing the function with its result doesn't change the behaviour of the application. A function has no side-effects if it doesn't rely on or alter anything outside of its local scope.

As I mentioned, the whole purpose of this blog series is to talk about FP in the context of Python, so let's look at an example of a pure Python function:

```python
# ✨ Pure ✨
# ✅ Referentially transparent
# ✅ No side-effects
def pure_add(a: int, b: int) -> int:
    return a + b
```

The aptly-named function above takes two integers and returns their sum. Based on the criteria I gave above, the function adheres to the definition of purity. An impure version of the function might look as follows:

```python
# 🤮 Impure 🤮
# ❌ Referentially transparent
# ❌ No side-effects
def impure_add(a: int, b: int) -> int:
    print(f"Adding {a} and {b}.")
    return a + b
```

This function is impure because it fails against both the criteria we set. Firstly, it isn't referentially transparent because, whilst the same input evaluates to the same result, we couldn't replace calls to the function with that result whilst maintaining the same application behaviour. Namely, if we just substituted the value `3` everywhere we saw `impure_add(1, 2)`, then the application wouldn't be the same because we'd no longer print anything to the console. Secondly, the act of printing is itself a side-effect because it's an I/O operation; it reaches out and communicates with the outside world, affecting something outside the scope of the function.

The practical implications of functional purity were quite surprising to me. If we can't do something as simple as print to the console in a pure function, then what else can't we do? Well, in a truly pure function (and this is by no means an exhaustive list), we can't:

* Log
* Interact with files, databases or REST APIs
* Generate random numbers
* Raise exceptions

At this point you'd be sensible to question what exactly the point of a pure function is if they can't really do anything. An important point to keep in mind is that a lot of the things we'd want to do in a function that would introduce impurity (at least in the context of data engineering), are typically I/O operations. The problem is that *code without side-effects doesn't do anything useful*. At the bare minimum if, as a data engineer, I can't read or write data, then I can't do my job.

If we think about where the impurity in a typical data pipeline lies, it’s mostly confined to the “edges” since those are the places where we need to perform I/O to read and write data. When we’re doing the bulk of our work (i.e., when we’re actually transforming data), our functions will generally take some data in and apply a series of functions to that data which produce a predictable result. Does that mean our functions will always be pure though? No. It’s certainly the case that a lot of our functions are likely to be pure, but at a minimum, we’re going to want some level of exception handling and logging.

We’re saying then that despite our best intentions, impurity in our functions is pretty much unavoidable, but we’re also saying that FP is all about composing pure functions, so what gives? In functional languages (like Haskell, F#, Scala etc.), the usual solution is to use something called a Monad and we'll dive into what they are and how they work in the rest of this series.
