+++
author = "Jamie Hargreaves"
title = "Pragmatic Functional Programming in Python - Part 3: Applicatives"
date = "2023-01-11"
description = ""
tags = [
]
+++

!["Northern lights over a mountain"](/images/pragmatic_functional_programming/sunset.jpg)

## We're *still* not talking about Monads?!

In [the last post in this series](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-2-functors/) we talked about Functors and how they could help keep functions pure (in our case when dealing with exceptions), and how they provided a mechanism to compose functions with their `map` method. We also talked about the road to understanding Monads and how an understanding of Functors and Applicatives was fundamental to that journey. So, before we *finally* talk about Monads, let's talk about Applicatives.

## Currying

In [the first post in the series](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-1-what-makes-code-functional/) one of the "FP buzzwords" I mentioned was currying. As well as being a buzzword, it's also an important technique to understand when it comes to using Applicatives. Currying is is essentially the process of taking a multi-parameter function and turning it into a chain of multiple single-parameter functions whose arguments can be applied sequentially. Why we'd want to do that will become clear soon, but let's quickly look at an example of a curried Python function. Python itself doesn't support currying natively but PyMonad comes with built-in support for it:

```python
from pymonad.tools import curry

@curry(2)
def add_n(n: int, a: int) -> int:
    return a + n
```

In the above function we've used `curry` as a decorator and specified the number of parameters to be curried (in this case, two). If what I've said about currying is true, then we should be able to call `add_n` successively, one argument at a time:

```python
add_one = add_n(1)

# 2, 2
print(add_n(1)(1), add_one(1), sep=", ")
```

As promised we can directly apply arguments successively as in the first example, or we can define a new function constructed by applying only some of the arguments and then finish applying the remaining arguments later as in the second example. The concept of currying is very similar to partial application, the difference being that currying always (effectively) creates multiple functions each taking a single argument, whilst partial application can produce a function of arbitrarily many arguments depending on how many of its arguments we partially apply.

## Applicatives: like Functors but not

When we used `map` [in the previous post](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-2-functors/#encoding-exceptions-with-functors), I purposely composed functions which only took one argument. This is important because, fundamentally, function composition takes the result of one function and passes that single result as the argument to the next function in the chain. So how do we compose functions when some of those functions expect to receive multiple arguments? As we just saw, currying gives us a simple way to convert multi-parameter functions into multiple functions, each with a single parameter.

When we created the curried `add_n` function we saw that it effectively acted like two chained functions, so in theory we should now be able to use it function composition, right? Let's use [the divide function we wrote in the last post](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-2-functors/#encoding-exceptions-with-functors) and see:

```python
result = (
    divide(1.0, 2.0)
    .map(add_n)
    # Erm...what now?
)
```

The above code might look stupid (and obviously doesn’t work), but this is exactly what I tried to do when first learning about FP and I was a bit stumped as to what to do next (it was also when I realised I didn't really understand Monads). How do we pass an argument from outside of the chain into the curried function? Well, we can't use `map` because if we think back to the type signature of `map` we know it acts on a Functor and applies a normal function to the wrapped value, returning the result wrapped in the same Functor. So what do we do?

This is where Applicatives come in. As with Functors, Applicatives all define particular method, this time called `amap` (think *Applicative map*). Let's look at the type signature of a simple `amap` method:

```python
def amap(self: "Applicative[Callable[[T], U]]", value: "Applicative[T]") -> "Applicative[U]": ...
```

We can see that `amap` acts on a function wrapped in an Applicative and takes a value wrapped in an Applicative as an argument, it then applies the wrapped function to the wrapped value and returns the result wrapped in an Applicative. How does that solve our problem? Well, `Either` is a Functor because it defines a `map` method, but it's also an Applicative because it defines an `amap` method. In the context of `Either`, `amap` has two branches:

* If the underlying value is wrapped in `Right`, then `amap` unwraps the value, unwraps the Applicative function, applies the unwrapped function to the unwrapped value and then returns the result wrapped in `Right`.
* If the underlying value is wrapped in `Left`, then `amap` does nothing and returns that same value wrapped in `Left`.

In the previous example, we'd use `amap` like this:

```python
result = (
    divide(1.0, 2.0)
    .map(add_n)
    .amap(Right(0.5))
)

# Result: 1.0
result.either(
    lambda left: print(left.__name__),
    lambda right: print(f"Result: {right}")
)
```

As promised, we’ve been able to use `amap` to pass in a value from outside of the composition chain into a curried function wrapped in an Applicative. Notice that we also need to wrap the value we want to pass into the curried function in an Applicative, in this case `Right(0.5)` rather than just `0.5`, because, by definition, `amap` applies a function wrapped in an Applicative to a value wrapped in an Applicative (look back at the `amap` type signature if it’s not clear).

As with Functors, there's really not all that much to Applicatives (not least because most Functors are also Applicatives) - for something like `Either` the differentiation between Functor and Applicative is almost academic. In practice, `Either` is just a useful class that let's us keep functions pure and which gives us some useful methods: one to chain together single-valued functions, and one to allow us to chain together curried,  multi-parameter functions.
