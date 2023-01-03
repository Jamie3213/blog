+++
author = "Jamie Hargreaves"
title = "Pragmatic Functional Programming in Python - Part 2: What the Hell is a Functor?"
date = "2023-01-03"
description = ""
tags = [
]
+++

!["Northern lights over a mountain"](/images/pragmatic_functional_programming/northern_lights.jpg)

## I thought we were going to talk about Monads?

Monads are probably the most off-putting concept in functional programming (FP), or at least they were for me. Despite how complicated they can seem at first, I don’t think “being complicated” is the reason that Monads are so off-putting, I think it’s because they’re almost universally explained in the context of Haskell.

I won't go too deep on Haskell here (would that I could), but the TL;DR is that Haskell is a popular, purely functional programming language. This means that (unlike Python), Haskell is quite specific about how it expects code to be written and doesn't let you just mix and match your paradigms any which way you please. The reason this matters to people like us is that a good chunk of FP resources are framed in the context of Haskell which can make learning about FP a real grind in the early stages (though if you are interested, there's probably no better place to start than [*Learn You a Haskell for Great Good*](http://learnyouahaskell.com)).

To talk about Monads we need to first talk about Functors and Applicatives. This is the first place that really tripped me up when I started learning about FP because most intros start from Monads and skip Functors and Applicatives entirely which can cause a lot of confusion when it comes to understanding and using Monads in practice (at least in my experience). The best explanation I’ve found on the topic is a blog by [Adit Bhargava](https://twitter.com/_egonschiele) entitled [*Functors, Applicatives and Monads in Pictures*](https://adit.io/posts/2013-04-17-functors,_applicatives,_and_monads_in_pictures.html). I don’t necessarily think there’s a lot I can add on top of this blog in terms of the fundamentals but what I can do is to re-frame things in the context of Python and provide some practical examples.

## Exceptions in pure functions

If you read [the previous post in this series](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-1-what-makes-code-functional/) you'll recall that one of the things in my list of useful things that pure functions can't do was exception handling. An example of why (in the context of data engineering), is a function which takes a dataframe, applies some transformations and returns a new dataframe. If we had a try/except block in the function that (magically) caught out of memory exceptions and returned some default dataframe whenever one occurred (however implausible), then we could imagine a situation where the hardware configuration of the system could alter the value the function returns; a single-node cluster might return one dataframe whilst a large, multi-node cluster might return another. A function like that clearly wouldn't be referentially transparent since it wouldn't produce a deterministic result.

That's *handling* exceptions, but what about *throwing* exceptions, is that a problem? The answer is a distinctly dissatisfying...🤷‍♀️. I've honestly never found anything particularly clear on this either way. In general though, we tend to avoid throwing exceptions in FP because we have alternate ways to handle them.

## Encoding exceptions with Functors

One functional alternative to throwing exceptions is to use a Functor called `Either`. You can think of a Functor as way to encode some kind of behaviour associated with a value (in this case, the occurrence of an exception). The `Either` Functor is a bit like a class with two sub-classes, `Left` and `Right`, which encode failure and success, respectively.
Let's think about a simple example of a function which raises an exception given a bad input:

```python
def divide(a: float, b: float) -> float:
    return a / b
```

When the value of `b` is zero, rather than returning, the function raises a `ZeroDivisionError`. Since the cause of the exception is wholly deterministic, we can use the [PyMonad](https://github.com/jasondelaat/pymonad) implementation of `Either` to re-write this function in a way that avoids the exception entirely:

```python
from pymonad.either import Either, Left, Right

def divide(a: float, b: float) -> Either[ZeroDivisionError, float]:
    return Left(ZeroDivisionError) if b == 0 else Right(a / b)
```

Unlike the previous version, the new version of our function always returns a predictable result of type `Either[ZeroDivisionError, float]` - it encodes the occurrence of an exception without actually raising one and crashing the program.

## Pure functions tell us about the good days *and* the bad days

Whilst the purity of throwing exceptions seems up for debate, there's actually an arguably better reason (IMO) to avoid it, one which is hit home in the *Pure Function Signatures Tell All* chapter of the fantastic book [*Functional Programming Simplified*](https://alvinalexander.com/scala/functional-programming-simplified-book/) by Alvin Alexander. The crux of it is that our original function didn't give us any indication that it might raise an exception, it told us that takes two floats and returns a float, but that isn't always true. Whilst for a simple function like our original `divide` we can easily look at the implementation and deduce when an exception would be raised, that's not always going to be the case with most functions we encounter. On the other hand, our new "Functorised" version of `divide` is totally honest; it tells use about the good days *and* the bad days - when things go well, it returns a `float`, when they don't, it returns a `ZeroDivisionError`.

## I have this dream where I'm trapped in a Functor and I can't get out 😰

How do we actually get values out of a Functor? Remember, if we call `divide(1.0, 2.0)`, we don't return `0.5`, we return `Right(0.5)`. In most languages we'd use something called structural pattern matching (which Python does support), however due to the implementation in PyMonad, we need to use the Functor's `either` method:

```python
success = divide(1.0, 2.0)
failure = divide(1.0, 0.0)

# Result: 1.5
success.either(
    lambda left: print(left.__name__),
    lambda right: print(right)
)

# ZeroDivisionError
failure.either(
    lambda left: print(left.__name__),
    lambda right: print(right)
)
```

The `either` method takes two functions, one which is called when the value is wrapped in `Left`, and another when the value is wrapped in `Right`. In both cases, we're just printing the result to the console. This in itself is a bit sketchy because, in the first post in the series, I specifically said that printing was impure. However, the key thing here (as I also pointed out then), is that ultimately we're always going to need to do some side-effecting actions (or why are we even writing code in the first place), so the question is more *how* we handle those actions rather than whether we handle them at all - in a subsequent post we'll look at an alternate way to do things like this.

## Composing functors with `map`

We've seen how we can drag a value kicking and screaming out of a Functor, but what happens when we want to pass a value wrapped in a Functor into a normal function? Well, one thing we could do is make all of our functions aware of the concept of a Functor and account for that in the implementation, but that seems like a lot of work. What we actually do is make use of a method that all Functors define called `map` (in other languages this is also called `fmap`). This method is really the secret sauce of a Functor and it's the mechanism that lets us compose Functors together. To get a better idea of how `map` works, let's look at the type signature of a generic implementation:

```python
def map(self: "Functor[T]", function: Callable[[T], U]) -> "Functor[U]": ...
```

From the type signature we can see that `map` acts on a Functor of type `T` and takes a single argument which is a function taking a value of type `T` and returning a value of type `U`. With this function, `map` then returns a value of type `U` wrapped in a Functor.

In the context of `Either`, `map` has two branches:

* If the underlying value is wrapped in `Right`, then we apply the function to the underlying value and return the result wrapped in `Right`.
* If the underlying value is wrapped in `Left`, then we do nothing and return that same underlying value wrapped in `Left`.

In practice, using `map` would look something like this:

```python
add_ten = lambda a: a + 10
multiply_by_two = lambda a: a * 2
cube = lambda a: a ** 3

result = (
    divide(4.0, 2.0)
    .map(add_ten)
    .map(multiply_by_two)
    .map(cube)
)

# Result: 13,824
result.either(
    lambda left: print(left.__name__),
    lambda right: print(f"Result: {int(right):,}")
)
```

This should help to sell the first criteria I spoke about in the previous post around code that’s easy to read and understand. For data engineers, this will look very similar to the style of method chaining used in Spark (which is sometimes referred to as *fluent interfaces*), and is very natural way to chain together a series of transformations in a more general Python context.

Hopefully you can see that there isn’t *that* much to Functors: they wrap values to encode some kind of behaviour to help keep our functions pure, and they give us a nice mechanism to chain results together in function composition. In the next post we'll continue our journey towards Monads by seeing how Applicatives fit into the mix.
