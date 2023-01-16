+++
author = "Jamie Hargreaves"
title = "Pragmatic Functional Programming in Python - Part 4: We're Finally Talking About Monads"
date = "2023-01-15"
description = ""
tags = [
]
+++

!["Some weird (pretty) green swamp thing"](/images/pragmatic_functional_programming/green.jpg)

## It's about time

In the previous posts in the series, we worked up to talking about Mondas by first discussing the idea of [Functors](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-2-what-the-hell-is-a-functor/) and [Applicatives](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-3-what-the-hell-is-an-applicative/), which I said were pre-requisite to properly understanding Monads. We're finally ready then to talk about Monads, unfortunately it may be a little anti-climactic because, as you might have guessed, you've been looking at a Monad all along. Throughout the series, we've been looking at `Either` and how it could be used in exception handling. Initially, I told you that `Either` was a Functor because if defined a `map` method, and then that it was an Applicative because it defined an `amap` method - as it turns out, it's also a Monad.

To me, this is why Monads can be so confusing. In FP, we talk about Monads like `Either`, but we usually neglect to mention that these Monads are also Functors and Applicatives. For me, that always made it difficult to concretely define the behaviour of a Monad. Because we always talk about these structures as Monads rather than as Functors or Applicatives, we usually talk about *Monadic values* and *Monadic functions* as well, so we say that values wrapped in a Monad are Monadic values and that functions taking non-Monadic values and returning a Monadic value are Monadic functions. It’s worth noting however that not all Monads are Functors or Applicatives; if you look at the `Writer` Monad [implementation in PyMonad](https://github.com/jasondelaat/pymonad/blob/release/pymonad/writer.py), for example, it defines a `map` and a `bind` method, but not an `amap` method, so it’s not an Applicative.

## Wait...what's `bind`?

Just like Functors and Applicatives, the special thing about a Monad is a method it defines called `bind` (sometimes it's referred to as *Monad bind*). The type signature for a generic `bind` method might look something like this:

```python
def bind(self: "Monad[T]", function: Callable[[T], "Monad[U]"]) -> "Monad[U]": ...
```

From the type signature you can see that `bind` is almost identical to `map` except for the fact that the function passed to `bind` returns a Monadic value, whereas the function passed to `map` returns a non-Monadic value. Where is `bind` useful? Well, it's useful in any situation where we're composing Monadic functions, for example, a chain of functions, each of which accounts for various exceptions by returning an instance of the `Either` Monad. We can see `bind` in action with a slightly altered version of the Monadic `divide` function we defined in a previous post:

```python
from pymonad.either import Either, Left, Right
from pymonad.tools import curry

@curry(2)
def divide(b: float, a: float) -> Either[ZeroDivisionError, float]:
    return Left(ZeroDivisionError) if b == 0 else Right(a / b)

divide_by_three = divide(3.0)
double = lambda x: 2 * x

result = (
    divide(1.0, 2.0)
    .map(double)
    .bind(divide_by_three)
)

# Result: 1.3
result.either(
    lambda left: print(left.__name__),
    lambda right: print(f"Result: {round(right, 1)}")
)
```

Note that if we'd used a call to `map` instead of `bind`, the code would still have worked; the difference is that `bind` returns `Right(...)` whilst `map` returns `Right(Right(...))`, so in this sense, `bind` accounts for the use of a Monadic function by unpacking one level of wrapping for us. In languages like Scala, the equivalent of `bind` is implemented in a method called `flatMap` which hints at this flattening behaviour a bit more explicitly.

As with Functors and Applicatives, hopefully you can see that Monads aren’t really that scary when you dig into what they actually do. Hopefully, you also have a much clearer idea of how we use Monads (and Functors and Applicatives), to compose functions and escape some of the usual trappings of impurity, especially where exceptions are concerned. Obviously, the examples we’ve used have been contrived, but they demonstrate the traditional means by which to build functionality through the composition of pure functions using `map`, `amap` and `bind`. Ultimately, if you understand how those methods work, then you can apply that understanding to lots of other Functors, Applicatives and Monads, even if their inner workings are slightly different.

## The I/O Monad

I’d be remiss if I wrote a blog about Monads and neglected to mention the I/O Monad since, for better or for worse (probably worse), there’s a good chance it’ll be the first Monad you come across when you start delving into FP.

I've implied throughout this series that the `Either` Monad is a sensible choice for an I/O operation that might raise an exception, but if I were programming in Haskell (or maybe F# or Scala or some other highly functional language), then I’d probably be told I should be using the I/O Monad. I also mentioned [back here](https://jamiehargreaves.co.uk/posts/pragmatic-functional-programming-in-python-part-2-what-the-hell-is-a-functor/#i-have-this-dream-where-im-trapped-in-a-functor-and-i-cant-get-out-) that we were being a bit sketchy when we just printed straight to the console when we called the `either` method. Again, in functional languages, the I/O Monad would be our go-to here. We already know how Monads like `Either` work and that, broadly, all Monads implement similar behaviours, so how does the I/O Monad work?

`IO` in PyMonad has all the methods we’d expect to make it a Functor, an Applicative and a Monad, namely `map`, `amap` and `bind`. The way `IO` works is that it wraps the functionality that performs I/O and delays its execution until we call the Monad’s `run` method. A lot of times, the I/O Monad is described as containing the instructions to perform I/O, without actually performing it. How would we use `IO` in a Python program?

```python
import os

from pymonad.io import IO, _IO

def get_env(var: str) -> _IO[str]:
    return IO(lambda: os.environ[var])

def put_str_ln(line: str) -> _IO[None]:
    return IO(lambda: print(line))

os.environ["LINE"] = "An example of using the I/O Monad."
result = get_env("LINE").bind(put_str_ln)

# <pymonad.io._IO object at 0x10ac7f190>
print(result)

# This is an example of using the I/O Monad in Python.
result.run()
```

We can see that without calling `run` we just return an instance of `_IO` and the wrapped code is never actually executed. Notice in this example that I’ve used functions like  `get_env` and `put_str_ln` in the composition chain which both return an instance of `_IO`, why is that? The reason is that if we included something like the `divide` function from earlier which returns an instance of the `Either` Monad, then the I/O Monad’s `bind` method wouldn’t know how to handle the fact that `divide` returns `Either` and not `_IO`. We can see this explicitly if we look at the type signature of the `_IO` class’s `bind` method in the PyMonad source code:

```python
def bind(self: "_IO[T]", function: Callable[[T], "_IO[U]]") -> "_IO[U]": ...
```

In languages like Haskell and Scala, the solution to this kind of problem would be to use something called a Monad transformer which allows us to stack the behaviour of different Monads and use them as though they were one. Unfortunately, PyMonad doesn’t support this feature, and this is one of the reasons I didn’t bother using `IO` previously. I also don’t particularly like the implementation in that `IO` is a function which returns an instance of the private (in the Python sense) `_IO` class that we’re not really supposed to use (though it's nice that we can still sub-type it if we really want to). In addition, notice that if there was an error in `get_env`, then our code does nothing to handle it and our program would still blow up. This is another example of why the ability to use a Monad transformer is useful if we’re going to start using things like `IO`, since we could combine the functionality of `IO` with something like `Either` or `Maybe`.

## Is there a downside to not using the I/O Monad?

It’s worth pointing out that the I/O Monad doesn’t somehow magically make our code pure (though there are plenty of arguments to the contrary). The reasoning from people who argue that the I/O Monad *does* make a function pure is usually along the lines that since it delays the execution of the internal function it wraps, it’s referentially transparent and itself doesn’t actually produce side-effects – every time we call the function, we always return an instance of `_IO`. Personally, even if that reasoning is technically correct, it feels a bit esoteric. Is my function really pure just because I stop it executing for a while? Regardless of how you skin the cat, you’ll ultimately call the `run` method and the instructions that were taken directly from your “pure” function will cause an impure action to occur. If it looks like a duck, swims like a duck and quacks like a duck, then it’s probably a duck.

All the I/O Monad appearing in the type signature of a function should tell us is that the function is definitely impure or it wouldn’t need to use the I/O Monad in the first place (there’s supposedly a quote to this effect from Martin Odersky, the creator of Scala, but I couldn’t find it). For me, this is the main benefit of using `IO` over something like `Either` since, as we saw, `Either` can be used for more than just I/O related actions. Given the downsides (at least in Python), however, it doesn’t seem worth the trade off when building real-world functionality.

If we really want to make it obvious from a function’s type signature that the function performs I/O whilst still being able to manage exceptions with `Either` then, as suggested in [Functional Programming, Simplified](https://fpsimplified.com), we can define a type alias instead:

```python
import os
from typing import TypeAlias

from pymonad.either import Either, Left, Right

StringIO: TypeAlias = Either[KeyError, str]

def get_env(var: str) -> StringIO:
    try:
        return Right(os.environ[var])
    except KeyError as e:
        return Left(e)
```

In this way we achieve a few things:

* We’re able to handle and maintain information about an exception
* We make it clear in the type signature that the function is impure, and
* We’re able to more easily carry out function composition
