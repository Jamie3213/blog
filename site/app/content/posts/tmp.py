from typing import Callable


def say_something(something: str) -> None:
    print(something)


def twice(function: Callable) -> Callable:
    def wrapper(*args, **kwargs) -> None:
        function(*args, **kwargs)
        function(*args, **kwargs)
    return wrapper


say_something = twice(say_something)

# Hello, world!
# Hello, world!
say_something("Hello, world!")


