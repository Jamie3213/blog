+++
author = "Jamie Hargreaves"
title = "Practical Functional Programming in Python"
date = "2022-08-18"
description = ""
tags = [
]
+++

!["Header showing an image of a bookshelf"](/images/dynamodb_concurrency/header.jpg)

## Who cares?

Before we even begin getting into the details of functional programming (FP), let's clear up the most important question: *who cares?* In fact, not just who cares, but why should *you* care and why do *I* care?

Given that I've written this blog, I obviously find find the theory of FP interesting to some extent - maybe that will be the case for you too, maybe it won't. Less so than theory, what I'm really interested in is what FP can do for me. When I'm writing code I want it to satisfy three (loose) requirements:

* Clean - easy to read and easy to understand
* Easy to test
* Not error-prone (and easy to de-bug when there are errors)

If a programming paradigm can't help with these requirements, then I'm not interested. Luckily, I think FP can help to achieve all three of these things.

## What makes code functional?

Okay, so I've decreed without any actual evidence (we'll get to that soon), that FP can help you write better code, but what exactly makes code functional? When I first started learning about FP the answer to that question was surprisingly elusive. After a lot of reading and YouTube-ing, I came across [a talk](https://www.youtube.com/watch?v=e-5obm1G_FY) by Anjana Vakil from JConf about FP. In that talk Anjana references a really great blog by [Mary Rose Cook](https://maryrosecook.com) called [*An introduction to functional programming*](https://codewords.recurse.com/issues/one/an-introduction-to-functional-programming) which hits home the fact that functional code is ultimately just code without side-effects. We can be a little more specific than this though:

> Functional programming is about building functionality through the composition of pure functions.

There are two parts to that statement, one is about function composition and the other is about pure functions. Let's start with the latter: what exactly is a pure function? A pure function is any function which satisfies the following two criteria:

* The same inputs always give the same output
* No side-effects

Pure functions are sometimes called *deterministic* or *referentially transparent*, however both of these terms are a bit loose and don't have uniformly agreed upon definitions (for example, they're sometimes used just to refer to the first criteria), so I'm going to stick with pure.

Let's take a look at an example of a super simple, pure function in Python which takes two integers and returns their sum:

```python
# ✨ Pure ✨
# ✅ The same inputs always give the same ouput
# ✅ No side-effects
def add(a: int, b: int) -> int:
    return a + b
```

It's fairly clear that the above function is pure based on the criteria I described above, so now let's alter it to introduce some impurity:

```python
# 🤮 Impure 🤮
# ✅ The same inputs always give the same ouput
# ❌ No side-effects
def add(a: int, b: int) -> int:
    print(f"Adding {a} and {b}.")
    return a + b
```

Hmm, okay, so now our new function is impure because, although the same inputs always give the same output, the function is side-effecting; that is to say it reaches into the outside world (so to speak), and prints some information to the console. Is that surprising to you? It was definitely surprising to me when I realised what the restrictions on a pure function mean in practice. What are some other things a pure function can't do then? Well, a pure function can't:

* Log to the console or to file
* More generally, read or write files at all
* Generate random numbers
* Call a REST API
* Interact with a database
* Raise exceptions

At this point you'd be sensible to question what exactly the point of a pure function is when I've just told you that they can't really do much of anything. A really important point to keep in mind is this:

> Code without side-effects doesn't do anything useful.

So code without side-effects is useless and pure functions don't have side-effects, therefore pure functions are useless, right? Well, since I'm a data engineer, let's think about this in a more contextualised way; consider the following ultra-generic data pipeline:

!["A super simple, generic data pipeline"](/images/functional_programming_in_python/data_pipeline.png)

There's nothing crazy going on here; we take some source data, land it into a raw/bronze area of a data lake (maybe it's a Delta lake), apply some cleansing and transformation to the data and move it into the silver area, then finally we apply some aggregations and move it into the gold area where it can be used as a basis for business reporting.

What does this have to do with fuctional purity? Well, if we think about where the impurity in the pipeline lies, it's mostly confined to the "edges". The primary places we'd need impure code are the places where we read or write data (i.e., perfom I/O). When we're doing the bulk of our work - i.e., when we're acually transforming data - our functions should really be pure, they should take some kind of source data, apply a series of transformations and produce an output...right?

Hmm, is it obvious that during transformation our functions would always be pure? No, not necessarily. Maybe *a lot* of out functions would be pure and it's definitely the case that the same inputs should always give the same output, but it's unlikely to be the case that we'll *never* need side-effects. Specifically, we probably want some level of logging and exception handling, even if it's not in all of our functions.

Okay, so if we're saying that side-effects are unavoidable, even if a good proporition of our functions are genuinely pure, how does FP solve the problem? Enter the Monad.

## Functors, Applicatives and Monads

Monads are probably the most off-putting concept in FP, or at least they were for me. Despite how complicated they can seem at first, I don't actually think that "being complicated" is the reason that Monads are so off-putting. I think Monads are off-putting because they're almost universally terribly explained, by which I mean "explained in the context of Haskell".

### Aside: Haskell

Python isn't a purely functional programming language and it's also not a purely object-oriented language either. It's a very flexible, general-purpose language that allows us to mix and match different programming paradigms and styles. Haskell isn't like this. That's not to say Haskell is bad in any way, it's simply to say that Haskell takes a much stricter view on how programs should be constructed. Haskell is a purely functional programming language and is one (if not *the*) most popular purely functional programming langauge there is.

Why does that matter? It matters because as a beginner learning about FP, you'll quickly notice that whenever you're reading a thread on StackOverflow about an FP concept that's confusing you, or whenever you're reading one of the myriad blogs about Monads, the authors seem to be unable to talk about either without also talking about (and writing) Haskell. It shouldn't really be surprising that some of the most knowledgeable people in the area of FP are people who write in a purely functional langauge, but that doesn't make it any less daunting. In addition, it's also *really* important to appreciate that just because something makes sense in Haskell, doesn't necessarily mean it's the right solution in other languages. Haskell makes decisions which are fundamentally driven by the fact that it is a purely functional language. In a sense, this is similar to the way that Python enforces a Global Interpreter Lock (GIL); this fundamental feature of the language means that in Python we employ certain techniques to handle threading and multi-processing, but in a langauge that doesn't enforce a GIL (like Java), those same techniques might not be applicable.

One of the biggest challenges is that Haskell doesn't really look (to me at least), like any of the languages I've come across before. It uses weird symbols everywhere, it doesn't use brackets around function arguments, all the functions are automatically curried which makes type signatures hard to comprehend (we'll talk about currying later, don't worry), and overall it just feels overwhelming to look at and understand.

For those reasons, I'm not going to talk about Haskell anymore in this blog. From now on, the only programming language I'm going to be using or talking about is Python.

### What the hell is a Functor?

Okay, I've rambled about Haskell, so now let's get back to Monads. To do that though, we need to talk about them in relation to two other things: Functors and Applicatives. This is the first place that tripped me up when I got into FP. Before I tried to use Monads in practice I hadn't even *heard* of Functors or Applicatives and it was only when I started using Monads that I realised there were some pieces of the puzzle missing, but didn't know what those pieces were.

The best explanation I've found of Functors, Applicatives and Monads is in a blog by [Adit Bhargava](https://twitter.com/_egonschiele) aptly entitled [*Functors, Applicatives and Monads in Pictures*](https://adit.io/posts/2013-04-17-functors,_applicatives,_and_monads_in_pictures.html). Now, I don't think I can do better than the explanation here, so feel free to just read the post (fair warning though, it's written in the context of Haskell). That being said, what I *can* do is explain Functors, Applicatives and Monads in the context of Python and, for me, this was awlays the biggest gap to plug when tackling any aspect of FP.

At their heart, Functors, Applicatives and Monads are all ways to wrap an object up inside some kind of *computational context*; the context itself can vary depending on the situtation, but all contexts share some common features. Sometimes (in fact, most of the time), you'll also hear Functors, Applicatives and Monads referred to in terms of a box that we put values into.

As with most things, it's easier to understand with an example. I mentioned earlier that we're always going to want to perform exception handling, but in a pure function we can't raise exceptions because that would involve side-effects. In FP, one solution to this problem is a Functor called `Either`. You can think about `Either` like a class with two sub-classes: one is called `Left` and the other is called `Right`, representing failure and success, respectively. Let's consider a simple function that will raise an exception under certain conditions:

```python
def divide(a: float, b: float) -> float:
    return a / b
```

Obviously this function divides two numbers, however if the denominator `b` is zero, then rather than returning a result, the function raises a `ZeroDivisionError` and crashes the program. As we discussed earlier, raising an exception introduces impurity into a function because it introduces a side-effect; it's also misleading. Whilst we can look at the implementation of this function and spot that it will raise an exception when `b` is zero, there's nothing about the function that inherently let's us know an exception could be raised. Looking at the type signature, we're told that our function takes two floats and returns a float...that's it.

How can `Either` help? Let's consider an alternate version of the function that uses the `Either` implementation from [PyMonad](https://github.com/jasondelaat/pymonad):

```python
from pymonad.either import Either, Left, Right

def divide(a: float, b: float) -> Either[ZeroDivisionError, float]:
    if b == 0:
        return Left(ZeroDivisionError("Tried to divide by zero."))
    else:
        return Right(a / b)
```

The new (let's call it "Functorised"), version of our function is much more informative. Without knowing anything about the implementation details, the type signature tells us that the function takes two floats and *either* returns a specific error *or* returns a float. What's more, when we do pass `b` as zero, nothing blows up, we still return a value whose type is `Either[ZeroDivisionError, float]` and our function exits cleanly - we've handled the exception but managed to maintain functional purity. If we want to know which path our function took, then we can check with the `either` method:

```python
success = divide(1.0, 2.0)
failure = divide(1.0, 0.0)

# Result: 0.5
success.either(
    lambda left: print(f"{type(left).__name__}: {left}"),
    lambda right: print(f"Result: {right}")
)

# ZeroDivisionError: Tried to divide by zero.
failure.either(
    lambda left: print(f"{type(left).__name__}: {left}"),
    lambda right: print(f"Result: {right}")
)
```

There are two things to say here. Firstly, the idea of the `either` method is a bit of an oddity and in most functional languages like Haskell and Scala we'd use structural pattern matching to determine the Functor's type. Due to the way `Either` is implemented in Python (namely that `Right` and `Left` are both functions that return an instance of `Either`, rather than sub-classes in their own right), we can't use Python's structrual pattern matching syntax. Secondly, we're already doing something a bit sketchy in this piece of code because the lambda functions we pass as the two arguments to the `either` method are actually both side-effecting because they print either the result or the exception to the console. For now, don't worry too much about it. Recall that our `divide` function itself is still pure and that, ultimately, we're always going to end up doing some side-effecting actions, so the question is more about *how* we do them rather than *whether* we do them. Later on we'll see a Monadic way to handle actions like this. That was a fairly trivial example, but hopefully it made it clear how a Functor like `Either` can be useful. 

Let's say that I've now applied my `divide` function to some values and obtained a result; what happens if I want to pass that result into another function? Let's see:

```python
def add_one(a: float) -> float:
    return a + 1

result = divide(1.0, 2.0)

# TypeError: unsupported operand type(s) for +: 'Either' and 'int'
division_plus_one = add_one(result)
```

Remeber that, whilst the actual act of division returns a float, our `divide` function doesn't - it returns a float wrapped in a Functor. As such, when we try to pass the Functor into `add_one`, we get a `TypeError` because Python doesn't know how to add an `int` to an `Either`.

This is where the magic of a Functor comes into play. A Functor in Python can be thought of like a class which defines a method called `fmap` (think *Functor map*). The implementation of the method can be different for different Functors, but crucially the job of `fmap` is to take a Functor like `Either` and apply a normal, non-Functorised function like `add_one` to it, returning another Functor of the same type. For `Either`, `fmap` has two branches:

* If the Functor value is wrapped in `Right` (i.e., everything was successful), then we apply the non-Functorised function to the underlying value and return the result wrapped in `Right`.
* If the Functor value is wrapped in `Left` (i.e., something went wrong), then we do nothing and return that same value wrapped in `Left`.

With our `add_one` example, using `fmap` (just called `map` in the most recent version of PyMonad), would look like this:

```python
success = divide(1.0, 2.0)
success_plus_one = success.map(add_one)

# Result: 1.5
success_plus_one.either(
    lambda left: print(f"{type(left).__name__}: {left}"),
    lambda right: print(f"Result: {right}")
)

failure = divide(1.0, 0.0)
failure_plus_one = failure.map(add_one)

# ZeroDivisionError: Tried to divide by zero.
failure_plus_one.either(
    lambda left: print(f"{type(left).__name__}: {left}"),
    lambda right: print(f"Result: {right}")
)
```

Perfect! So when the result from `divide` was successful, `map` takes the value wrapped in `Right`, adds 1 to it and returns that result wrapped in `Right` again. When the result from `divide` wasn't successful, `map` just skips applying `add_one` altogether and passes through the error that was returned from `divide`, still wrapped in `Left`.

We didn't say it explicitly, but we've also just seen how function composition works with Functors. Function composition is just the processes of applying functions consecutively to the results of other functions without the need to explicitly define the intermediate values. In general, if we had three functions `f(x)`, `g(x)` and `h(x)`, then we could get the result of applying them sequentially like this:

```python
f_restult = f(x)
g_result = g(f_result)
h_result = h(g_result)
```

However, that's the same thing as just composing the functions directly as `f(g(h(x)))` but, as mentioned, without the need for all the superfluous intermediate values. A Functor's `map` method gives us an extremely clean way to do this and is very similar aesthetically to the way method chaining works in frameworks like Spark (this is sometimes referred to as *fluent interfaces*). Let's imagine we want to call our divide function and then apply a series of other functions to the result; how would it look? Let's define a few toy functions to play with first:

```python
def add_ten(a: float) -> float:
    return a + 10

def multiply_by_two(a: float) -> float:
    return a * 2

def cube(a: float) -> float:
    return a ** 3
```

These are obviously trivial functions but hopefully they'll illustrate something really powerful about function composition in FP:

```python
result = (
    divide(4.0, 2.0)
    .map(add_ten)
    .map(multiply_by_two)
    .map(cube)
)

# Result: 13824.0
result.either(
    lambda left: print(f"{type(left).__name__}: {left}"),
    lambda right: print(f"Result: {right}")
)
```

Hopefully this really sells the first criteria I spoke about at the start of this blog around code that's easy to read and understand. With this style of function composition the logic of our application can be read almost in plain English. We can actually go one step further with PyMonad and use a method called `then` which dynamically picks between `map` and another method called `bind` (which we'll talk about soon). Using `then`, our code is even more expressive:

```python
result = (
    divide(4.0, 2.0)
    .then(add_ten)
    .then(multiply_by_two)
    .then(cube)
)
```

### Aside: partial application and currying

Before we move on to talking about Applicatives, I want to briefly talk about two similar concepts that we're going to use quite heavily throughout the rest of the blog: partial application and currying.

First, let's cover partial application. Previously we defined two functions, `add_one` and `add_ten`, which basically do the same thing and yet, rather redundantly, we defined them in two separate places. Obviously, we could instead define a single function:

```python
def add_n(a: int, n: int) -> int:
    return a + n
```

Using partial application, we could then define the `add_one` and `add_ten` functions in terms of our generic `add_n` function by fixing the value of `n`:

```python
import functools

add_one = functools.partial(add_n, n=1)
add_ten = functools.partial(add_n, n=10)

# 2
print(add_one(1))

# 11
print(add_ten(1))
```

When we call `functools.partial` we return a new function whose value is the old function with some of its argument values fixed. We can then apply this new, partially applied function to the remaining arguments to get a result.

Again, this was a contrived example, but in general partial application can be useful when we want to take a generic function and fix some of its arguments to make a new function which is more tailored to a specific use-case. It's worth pointing out that we can partially apply as many of a function's arguments as we want and, in fact, if we partially applied *all* the arguments we'd get a function which could be called without any arguments at all (though it's not likely we'd ever need to do that). In general, if we have a function of `p` arguments and partially apply `q` of them, then we get back a new function of `p - q` arguments.

Currying is a bit different. When we curry a function - named after the Mathematician [Haskell Curry](https://en.wikipedia.org/wiki/Haskell_Curry) (I wonder where else we've seen that name) - rather than turning a function of `p` arguments into a function of `p - q` arguments like in partial application, we take a function of `p` arguments and create `p` functions, each of a single argument. Erm...why? Well, currying has a very natural place when we compose functions using `map` like we did earlier.

We can create a curried version of our `add_n` function with the help of PyMonad:

```python
from pymonad.tools import curry

@curry(2)
def add_n(a: int, n: int) -> int:
    return a + n
```

If you're not sure about how we've used `curry` as a decorator here, then don't worry, we're going to talk about decorators quite a bit later but for now just know that they're a way to add additional functionality to a function without cluttering up the actual function definition itself. If what I've told you about currying is true, then `add_n` should actually be akin to two functions, each with one argument. Let's see:

```python
add_one = add_n(1)

# <function _curry_helper.<locals>._curry_internal at 0x100c896c0>
print(add_one)
```

As promised, when we can call `add_n` with a single argument, we get back a curried function. Now we can apply our curried `add_one` function to a second value to obtain a result:

```python
# 2
print(add_one(2))
```

As you can see, whilst partial application and currying are similar, they're each used in slightly different ways. In addition, Python only natively implements functionality for partial application and we have to use an external library to add currying functionality.

### What the hell is an Applicative?

Great, we know what partial application and currying are so we're now in a position to talk about Applicatives. When we used `map` to compose our functions earlier, I purposely used functions which only took one argument. This is important because fundamentally, function composition takes the result of one function and passes that single result as the argument to the next function in the chain. So how do we compose functions when some of those functions expect to receive multiple arguments? As we saw in the previous section, currying gives us a way to convert multi-argument functions into multiple functions of a single argument.

Let's look at another example. In the previous section we created a curried version of our `add_n` function. In theory, it should now act like two functions and so we should be able to use it in function composition like before, right? Let's see:

```python
result = (
    divide(1.0, 2.0)
    .map(add_n)
    . # Erm, what now?
)
```

The above code might look stupid (and obviously doesn't work), but this is exactly what I tried to do when first learning about Monads and I was a bit stumped as to what to do next. How do we pass an argument from outside of the chain into the curried function?

Let's re-trace our steps: we applied our `divide` function and returned an `Either` Functor, then we passed the value wrapped up in our Functor into our curried `add_n` function - what's the result of that action? Remember that `map` takes a Functor, applies a non-Functorised function to the value the Functor wraps and then returns the result wrapped in a Functor. So when we call `map(add_n)` we actually return a curried function wrapped in `Either` which means we can't just use another call to `map` since `map` doesn't know what to do with a curried function wrapped in a Functor.

We don't have a pattern to deal with this type of composition yet and that's where Applicatives come in. Similarly to Functors, an Applicative in Python is just a class that defines a method called `amap` (think *Applicative map* this time). The job of `amap` is to take a value wrapped in an Applicative and a function wrapped in an Applicative, then to apply the function to the value and return an Applicative. How does that help us with our problem? Well, `Either` is a Functor because it defines a `map` method, but it's also an Applicative because it defines an `amap` method. Just like `map`, `amap` is defined by two branches in the context of `Either`:

* If the value inside `Either` is `Right`, then `amap` unwraps the value and unwraps the Applicative function, applies the unwrapped function to the unwrapped value and then returns the result wrapped in `Right`.
* If the value inside `Either` is `Left`, then `amap` does nothing and passes the error through, returning `Left` again.

For our previous example, we can use `amap` as follows:

```python
result = (
    divide(1.0, 2.0)
    .map(add_n)
    .amap(Right(0.5))
)

# Result: 1.0
result.either(
    lambda left: print(f"{type(left).__name__}: {left}"),
    lambda right: print(f"Result: {right}")
)
```

As promised, we've been able to use our new `amap` method to pass in a value from outside of the composition chain into a curried function wrapped in an Applicative. Notice that we also need to wrap the value we want to pass into the curried function in an Applicative because, by defintion, `amap` applies a value wrapped in an Applicative to a function wrapped in an Applicative.

### What the hell is a Monad?

It's *finally* time to talk about Monads and, as you've probably gussed, I'm going to tell you that as well as being a Functor and an Applicative, `Either` is also a Monad! This is why (to me), Mondas can be so confusing. In FP, we talk about Monads like `Either` (as well as things like `Maybe`, `Writer`, `State`, `Reader` and so on), but we always fail to mention that these Monads are also Functors and Applicatives, and for me that always made defining concretely the behaviour of a Monad difficult. Because we always talk about these structrues as Monads rather than as Functors or Applicatives, we usually talk about "Monadic values" and "Monadic functions" as well, so rather than saying a function is "Functorised" (which I made up to try and avoid any early confusion), we normally say that a function taking non-Monadic values and returning a Monad is a Monadic function and that values wrapped in Monads like `Either` are Monadic values.

So then what behaviour does a Monad need to have? As with Functors and Applicatives, Monads define a certain method and, in this case, that method is called `bind` (sometimes referred to as *Monadic bind*). The `bind` method takes a Monadic value and a Monadic function (i.e., a function which takes non-Monadic values but returns a Monad), applies the function to the underlying value wrapped in the Monad, then returns the result wrapped in a Monad.

Where is `bind` useful? Well, let's imagine that we read some input from an environment variable (maybe it's a secret in a Lambda Function or Azure Function that redirects to a secret store). This is a natural place to use the `Either` Monad because the I/O operation could potentially return an error, for example, if the environment variable wasn't set or if our function didn't have permission to access the secret store. After we read the environment variable, we pass the value into a function which can also error and so also returns an `Either` Monad (two Monadic functions) - in this scenario we'd need to use `bind` to compose those two functions.

As a dummy verison of the above, let's write a program which reads a value from an environment variable, converts it to a float (since it'll be read in as a string), and passes it into a curried version of our Monadic `divide` function from earlier:

```python
import os

from pymonad.either import Either, Left, Right
from pymonad.tools import curry

def get_env(var: str) -> Either[KeyError, str]:
    try:   
        value = os.environ[var]
        return Right(value)
    except KeyError as e:
        return Left(e)

@curry(2)
def divide(b: float, a: float) -> Either[ZeroDivisionError, float]:
    if b == 0:
        return Left(ZeroDivisionError("Tried to divide by zero."))
    else:
        return Right(a / b)

def main() -> None:
    os.environ["NUMBER"] = "1.0"
    divide_by_two = divide(2.0)

    result = (
        get_env("NUMBER")
        .map(lambda number: float(number))
        .bind(divide_by_two)
    )

    result.either(
        lambda left: print(f"{type(left).__name__}: {left}"),
        lambda right: print(f"Result: {right}")
    )

if __name__ == "__main__":
    # Result: 0.5
    main()
```

Everything works as expected: we read our environment variable, use an anonymous/lambda function to convert the value from a string to a float, then pass the result into `divide_by_two` (which we created from a curried version of `divide`), and return the result. Notice that to use `divide_by_two` in composition in the way we'd expect, we have to flip the arguments in the function signature of `divide`. This is because when we call `divide(2.0)`, we fix the *first* argument of the function.

That's it, you now (hopefully) understand Functors, Applicatives and Monads and have seen how they can be used in Python using the PyMonad package!

### Aside: the I/O Monad

I'd be remiss if I wrote a blog about FP and didn't mention the I/O Monad because, for better or for worse (probably worse), there's a good chance it'll be the first Monad you come across when you start delving into FP.

I said in the previous section that the `Either` Monad was a sensible choice for an I/O operation that might raise an exception, but actually if I were programming in Haskell (I know I said I wouldn't talk about it again), or even something less functionally pure than Haskell but *much* more functionally pure than Python, like Scala, then I'd probably be told I should be using the I/O Monad. I also mentioned that we were being a bit sketchy earlier when we just printed straight to the console from within our `main` function and, again, in functional languages, the I/O Monad would be our Monad of choice here. We already know how Monads like `Either` work and that broadly all Monads imeplement similar behaviours, so how does the I/O Monad work (in Python, preferably)?

Well, the `IO` Monad in PyMonad has all the methods we'd expect to make it a Functor, an Applicative and a Monad (namely, `map`, `amap` and `bind`). The way the `IO` Monad works is that it wraps the functionality that performs I/O and delays its execution until we call the Monad's `run` method (in other languages this is sometimes called things like `unsafeRun`). How would we use the `IO` Monad in an actual program? Let's see:

```python
import os

from pymonad.io import IO

def get_env(var: str) -> IO:
    return IO(lambda: os.environ[var])

def put_str_ln(line: str) -> IO:
    return IO(lambda: print(line))

os.environ["NUMBER"] = "1.0"

def main() -> IO:
    return (
        get_env("NUMBER")
        .map(lambda number: float(number))
        .map(lambda number: number * 2)
        .map(lambda number: number + 3)
        .map(lambda number: number / 5)
        .map(lambda number: str(number))
        .bind(put_str_ln)
    )

# 1.0
if __name__ == "__main__":
    main().run()
```

We can see that this produces the result we expect but only *after* we call the `run` method on the `main` function's return value. If we'd only called `main`, then we'd have returned an `IO` Monad but wouldn't have executed any of the logic it was wrapping because `IO` delays the execution (it executes lazily, not eagerly).

Notice in this example that I've only used non-Monadic lambda functions or other `IO` functions like `put_str_ln` in the composition chain, why is that? The reason is that if we included something like the `divide` function from earlier which returns an `Either` Monad, then the `IO` Monad's `bind` method (which is responsible for applying a Monadic value to a Monadic function), wouldn't know how to handle the fact that `divide` returns `Either` and not `IO`.

In languages like Haskell and Scala, the solution would be to use something called a *Monad transformer* which allows us to stack the behaviour of different Monads and use them as though they were a single Monad. Unfortunately, PyMonad doesn't support this feature and this is the main reason I didn't bother using the `IO` Monad previously. In addition, notice that in the `IO` version of `get_env`, if there was an error, then our code does nothing to handle it and our program would still blow up. This is another example of why the ability to use a Monad transformer is useful if we're going to start using things like `IO`.

The quesion then is, is there a downside to not using the `IO` Monad? Well, it's worth pointing out that the `IO` Monad doesn't somehow magically make our code pure. Whether or not we use the `IO` Monad, we're still going to reach into the outside world and do some side-effecting actions. All the `IO` Monad appearing in the type signature of a function tells us is that the function is *definitely* impure (or it wouldn't need to use the `IO` Monad). For me, this is the main benefit of using the `IO` Monad over something like `Either`, but given the downsides (at least in Python), it's not really worth the trade-off.

If we really want to make it obvious in a function's type signature that the function performs I/O whilst still being able to manage exceptions (and as suggested in [Functional Programming, Simplified](https://alvinalexander.com/scala/functional-programming-simplified-book/), by Alvin Alexander), then we can define a type alias for `Either`:

```python
from pymonad.Either import Either, Left, Right

EnvironmentIO = Either[KeyError, str]

def get_env(var: str) -> EnvironmentIO:
    try:
        value = os.environ[var]
        return Right(value)
    except KeyError as e:
        return Left(e)
```

In this way we achieve a few things:

* We're able to handle and maintain information about an exception that might occur
* We make it clear in the type signature that the function is impure
* We're able to compose the function's result as normal

## Should we bother with Monads in Python?

I've just finished a nearly 5,000 word monologue about Monads and I think the fact it's taken me this long to give what I think is a sufficiently detailed explanation of how they work is quite telling. Not only that, but I only spoke about two Monads, `Either` and `IO`, but I brushed over the fact that there are tons of other Monads designed to tackle different problems. As I said earlier, I don't think that Monads are particularly complicated in principle, but I do think they're extremely unfamiliar.

At the start of this blog, the first criteria I said I wanted my code to adhere to was that it was clean, which I described as "easy to read and easy to understand". Earlier I argued that the Moandic code we wrote fulfils this criteria. After all, remember how nice the `then` syntax was and how we could read the code like we were reading plain English? I think it was a little misleading. Was it really the use of Monads that made our code so easy to reason about? No. We happened to use Monads to compose our functions, but it was function composition that made our code feel so clean, not Monads. What's more, what happens if someone needs to add new functionality to our code, say logging? Do they now need to start reading all about the `Writer` Monad and figuring out a way to replicate some kind of Monad transformer or start wrapping Monads in Monads to handle exceptions in code in which they also want to log?

Monadic Python code is easy to read and understand if you understand how Monads work, but by that logic, isn't all code easy to read and understand? "Easy to read and easy to understand" has to apply to a wider audience than just the person who wrote the code and has to be deeper than a superficial understanding after a quick once-over. In a professional setting, you're not the only person who needs to read, understand, maintain and extend the code you write.

Ultimately, my biggest criticism of Monads in Python is pretty simple: *Moands aren't Pythonic*. The idea of code being "Pythonic" might seem a bit ideological to you, after all does it matter if our code is Pythonic as long as it works? I think it does. The danger we get into when we start introducing concepts like Monads into our Python code is that it very quickly stops looking and, more importantly, behaving the way someone could reasonably expect Python code to look and behave. Especially in a professional setting, that's a problem. Imagine you're working on a project and you've made your entire codebase ultra-functional; exceptions are never thrown, everything is wrapped in `Either` and `IO` and all sorts of other Monads, all your functions are curried and so on ad nauseum. What happens when you move off the project and another Python developer takes over? Well, it should be fine right, they write Python and you've written Python? Not if the Python you've written looks like Haskell or Scala. The point is perfectly summed up by this Tweet:

{{< tweet user="BenLesh" id="1410045265449525248" >}}

Even better is the top reply:

{{< tweet user="jkup" id="1410046158693715970" >}}

My strong feeling is that if you're going to write your code in a way that means it ostensibly looks like Haskell (or Clojure or OCaml or F# or any other functional language you can think of), then you should just write your code in that langauge rather than trying to warp another language to the point of it looking alien to anyone else who develops in it. It's precisly for this reason that the title of this blog is *Practical* functional programming in Python. When it comes to FP we should be pragmatic, taking the parts of the paradigm that work for us and make our code better and not worrying ourseleves too much about the parts that don't.

You've gotten this far in the blog and I've essentially just told you that you should throw away everything you've read so far because none of it's Pythonic and you should never do it, right? No. Firstly, regardless of whether you decide to use Monads, I think an understanding of them is vital when learning about FP because you'll see them referred to everywhere. Secondly, your decision to use or not use Monads should be one made based on an understanding of the pros of cons of each choice, not because you read a blog where someone told you that using Monads in Python is bad.

If I'm saying that I don't like the Monadic approach to function composition and side-effecting in Python, what's my alternative?

## A Pythonic approach to functional programming

If I had to boil down Monads to the core things I think are useful about them, it'd be their ability to cleanly enable function composition and their ability to abstract and call out the side-effecting parts of my code. When it comes to the side-effects themseleves, I can't say I really care about them. As I pointed out before, there's nothing magic about using Monads like `IO` to handle side-effects; our code still produces them. When we use something like the `IO` Monad, all we've done is stick a massive label on a function that highlights the fact that it's side-effecting. What's more, even if I think the best way to handle errors is to use something like the `Either` Monad, most other people in the world don't, so when I'm building a data pipeline in Spark on Databricks and I want my pipeline to fail, the platform expects me to raise an exception in order to do that.

Unlike in software engineering where a large part of the application is typically under the control of the developer and something close to a purely functional approach might be reasonable, in data engineeering, we're typically working within some kind of big data framework (like Spark), and using cloud platforms like Databricks or EMR to run those big data applications. As such, we're nowhere near as free to do as we please and, as highlighted in the Databricks example, we often can't decide "I'm not going to raise exceptions in my code", because it's simply not practical.

### Abstracting behaviour with decorators

I said above that one of the two things I most like about Monads is the way in which they allow us to abstract and call out the side-effecting parts of our code. In Python, we don't need Monads to do this, we can use decorators.

Decoarators in Python are interesting to me because for a long time, they were completely *un*interesting to me. I thought decorators were a bit pointless and I couldn't really see why I'd ever need to use them outside of throwing a `@dataclass` decorator over a class every now and then.

How do decorators work? The crux of a decorator is that it let's us extend the functionality of a function without polluting that function with the implementation details of the extended functionality, usually because the extended functionality isn't unique to just that function. It's worth pointing out that [decorators in Python aren't the same as the Gang of Four's Decorator design pattern](https://stackoverflow.com/questions/8328824/what-is-the-difference-between-python-decorators-and-the-decorator-pattern).

One really nice example of how decorators work is when it comes to timing function execution. First, let's look at how we could time function execution without a decorator:

```python
import time

def hello_world() -> None:
    time.sleep(2)
    print("Hello, world!")

start = time.time()
hello_world()
end = time.time()

# Hello, world!
# Took 2.01 seconds.
print(f"Took {end - start:.2f} seconds.")
```

Now let's see how we achieve the same thing with a decorator:

```python
import time
from typing import Any, Callable, TypeVar

T = TypeVar("T")

def timeit(function: Callable[..., T]) -> Callable[..., T]:
    def wrapper(*args: Any, **kwargs: Any) -> T:
        start = time.time()
        result = function(*args, **kwargs)
        end = time.time()

        print(f"Took {end - start:.2f} seconds.")

        return result

    return wrapper

@timeit
def hello_world() -> None:
    time.sleep(2)
    print("Hello, world!")

# Hello, world!
# Took 2.01 seconds.
hello_world()
```

Hmm, okay we probably need to explain exactly what's going on here. The `@` notation we've used in front of `timeit` above the `hello_world` function is just syntactic sugar; behind the scenes, Python does the following when we decorate `hello_world` with `@timeit`:

```python
hello_world = timeit(hello_world)
```

Essentially, Python re-defines our function as the result of applying the decorator to the function. This makes sense if we look at the decorator's type signature. The type signature of `timeit` tells us that it takes a generic function as its argument and returns some generic function in response, namely, it returns the `wrapper` function defined within it. The `wrapper` function takes any number of non-keyword and keyword arguments, then passes them as the arguments to `function` returning whatever the return value of `function` is whilst also implementing the timing logic. Therefore, we could combine all of this without the syntatic `@` sugar and use the decorator as follows:

```python
timed_hello_world = timeit(hello_world)

# Hello, world!
# Took 2.01 seconds.
timed_hello_world()
```

The benefit of using the decorator approach to time function execution is that it's totally generic. Our `timeit` decorator doesn't care which function it's decorating, so we can shove `@timeit` on top of any function we like and it'll have the same effect. In addition, we've been able to extend the functionality of a decorated function without visually changing the implementation details of the function itself.

### Exception handling with decorators

We started talking about Monads by looking at how we could use them to perform exception handling, so now let's look at exception handling in the context of decorators. One thing I didn't like about our use of `Either` when we wrote our `divide` function earlier was that we still had to define the logic to return `Left` or `Right` inside the function. To me, this cluttered up the actual logic of the function. When we used `Either`, we used an if/else block to handle the case where the denominator was zero, but actually we could also have used a try/except block instead:

```python
from pymonad.either import Either, Left, Right

def divide(a: float, b: float) -> Either[ZeroDivisionError, float]:
    try:
        return Right(a / b)
    except ZeroDivisionError as e:
        return Left(e)
```

There's nothing special about the exception handling logic above: we try to do something and in the event of a specific exception, we do something else. There's no reason the try/except logic couldn't be it's own generic function:

```python
from typing import Any, Callable, Tuple, Type, TypeVar

T = TypeVar("T")

def try_except(
    function: Callable[..., T],
    catch: Type[Exception] | Tuple[Type[Exception], ...],
    throw: Type[Exception],
    throw_msg: str | None,
    *args: Any,
    **kwargs: Any,
) -> T:
    try:
        return function(*args, **kwargs)
    except catch as e:
        error_msg = str(e) if throw_msg is None else throw_msg
        raise throw(error_msg)
```

Our new `try_except` function has several arguments:

* A generic function containing the actual business logic
* A single exception or a tuple of exceptions to catch
* The cusom exception to raise if one of the exceptions to catch is encountered
* An optional error message to pass to the custom exception
* Any non-keyword and keyword arguments to pass to `function`

How would this work in practice? Let's see:

```python
import functools

class MySpecialException(Exception):
    pass

def divide(a: float, b: float) -> float:
    return a / b

# __main__.MySpecialException: Tried to divide by zero.
try_except(
    divide,
    ZeroDivisionError,
    MySpecialException,
    "Tried to divide by zero.",
    1.0,
    0.0
)
```

Okay, so this does what we expected it to do, namely it catches the `ZeroDivisionError` that's raised when we try to divide by zero and raises the custom exception we defined along with a custom error message. Great, but the above code looks very messy, so let's see if using a decorator can address that:

```python
def try_except(
    catch: Type[Exception] | Tuple[Type[Exception], ...],
    throw: Type[Exception],
    throw_msg: str | None,
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    def outer_wrapper(function: Callable[..., T]) -> Callable[..., T]:
        def inner_wrapper(*args: Any, **kwargs: Any) -> T:
            try:
                return function(*args, **kwargs)
            except catch as e:
                error_msg = str(e) if throw_msg is None else throw_msg
                raise throw(error_msg)

        return inner_wrapper
    
    return outer_wrapper
```

Now we have a decorator that we can use as before, however you'll notice that this decorator has both an inner and outer wrapper function. The reason for this is that previously our decorators didn't take any arguments, whilst this decorator takes three arguments. We can use the decorator with our `divide` function as follows:

```python
@try_except(
    ZeroDivisionError,
    MySpecialException,
    "Tried to divide by zero."
)
def divide(a: float, b: float) -> float:
    return a / b

# __main__.MySpecialException: Tried to divide by zero.
divide(1.0, 0.0)
```

This is almost perfect but even with the synatic decorator sugar, the fact we're passing multiple arguments into the decorator means it still looks pretty messy. We can fix this by defining a new decorator with the outer arguments already applied:

```python
maybe_my_special_exception = try_except(
    ZeroDivisionError,
    MySpecialException,
    "Tried to divide by zero."
)

@maybe_my_special_exception
def divide(a: float, b: float) -> float:
    return a / b

# __main__.MySpecialException: Tried to divide by zero.
divide(1.0, 0.0)
```

We can imagine that in production code the definition of the `try_except` decorator might live in its own module with other decorators or custom exceptions and that the `divide` function probably lives in another module along with other related code meaning the implementation details of the decorator are nicely abstracted away.

When we look at the definition of `divide` now, we've essentially achieved the same kind of expressiveness that the `Either` Monad gave us: we can see what the function returns under normal circumstances but also get a clear indicator that the function might also raise a specific error under certain conditions. In addition we've actually removed any hint of error handling boilerplate code from the function definition. The only difference from the the Monadic approach is that the error will actually be raised in our new implementation rather than being suppressed by the Monad and passed through in a composition chain. This is obviously impure, but personally, I don't care; I think this approach is much more Pythonic and also avoids reliance on any external libraries.

### Logging with decorators

The final application of decorators I want to look at is logging and, again, this is a problem that a typical FP langauge like Haskell would solve with Monads, namely the `Writer` Monad. PyMonad has a `Writer` implementation which works like most other implementations, however, we're not using Monads anymore, we're using decorators. If you are interested, [Learn You a Haskell For Great Good](http://learnyouahaskell.com) has a nice section on the `Writer` Monad [here](http://learnyouahaskell.com/for-a-few-monads-more).

We've already seen two examples of decorators and the great thing about them is that they all follow a very similar structure: we have an outer-most function into which we pass the decorator's arguments, an outer wrapper which receives the function we're decorating and finally an inner wrapper which takes the arguments we want to pass to the decorated function and which implements the extended functionality of the decorator.

Before we dive into implementing our logging decorator, let's think for a second about when we want to use logging. Broadly, I use logging either for informational purposes (i.e., to track function execution in a pipeline), or because an exception has been raised and I want to log it before the application exits. The latter case is interesting because I want the logging to occur regardless of the exception, i.e., I want to log the exception in the case where it was unhandled.

In my mind, there are broadly four kinds of exceptions I think about:

* Exceptions that I can anticipate, catch and recover from, e.g., I try and read a config file but fail and fall back to a default configuration.
* Custom exceptions that are either the result of checking a specific condition or catching some specific group of exceptions and then re-raising them under a more informational exception.
* Exceptions that I can anticipate, but that I can't necessarily do much about, e.g., I try to read a data file but the file doesn't exist.
* Exceptions that I can't anticipate or handle.

For the first option, I don't need to log an exception because I was able to anticipate and handle it (maybe I'd log a warning though so there was a trace that I did need to handle an error). For the second option, I'd need some custom exception handling logic in my functions, either something like the `try_except` decorator to catch and re-categorise exceptions, or some other logic to perform specific checks against function attributes, for example; in this case, I'd want to log the custom exception. For the third option, I just want to log the exception, and similarly for the fourth option.

Okay, what's the point of all of this? The point is, for the third and fourth options I risk writing redundant code that clutters up my functions. Consider a function which reads a local JSON file and returns it as a dictionary:

```python
import json

def read(file: str) -> dict:
    with open(file, "r", encoding="utf-8") as file:
        my_file = file.read()
    
    return json.loads(my_file)
```

This function could fail with a `FileNotFoundError`, so I could do something like this:

```python
import logging

logger = logger.getLogger()

def read(file: str) -> dict:
    with open(file, "r", encoding="utf-8") as file:
        try:
            my_file = file.read()
        except FileNotFoundError as e:
            logger.error(e)
            raise e
    
    return json.loads(my_file)
```

In the case where the file didn't exist, this would do the job and log the exception before raising it. But what's the point ot the try/except block here, does it *really* do anything useful? No. The only reason the try/except block is there is because we want to log the exception, we don't actually do anything useful and handle the exception, so it's annoying that we're bothering to catch it in the first place (or at least that we're bothering to overtly catch it *within* the logic of the function).

### Function composition with pipes

### Type hints and static type checkers

### Declarative over imperative: *what, not how*

### Stop trying to make map and filter happen

## Unit testing

### Defining a test unit in the context of data engineering

### Asserts aren't unit tests
