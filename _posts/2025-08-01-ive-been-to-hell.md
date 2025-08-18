---
layout: post
author: Jamie Hargreaves
title: I've Been to Hell and it Looks Like a Jupyter Notebook
date: 2025-08-01
permalink: /blog/ive-been-to-hell-and-it-looks-like-a-jupyter-notebook
tags: python spark etl
---

![Header showing a picture of a mountain range]({{ "/assets/img/pragmatic-fp-header.jpg" | relative_url }})

* TOC
{:toc}

## Data engineering in notebook hell

One of my biggest frustrations with data engineering as a discipline (and enterprise data platforms like Databricks and Microsoft Fabric), is the relentless and seemingly never-ending push towards notebooks as the primary mechanism to write and deliver code. For me, notebooks are synonymous with a scripting style approach to development that lends itself to a host of bad practices, but if they're so _obviously_ bad, why have they become so popular and why do platforms seem so intent on ecouraging their use? Well, several things come to mind:

* **Time-to-value:** notebooks take us from zero to _something_ quickly, they let us write code and interact with data with little to no setup, often inside the browser.

* **Versatility:** notebooks let us flit between multiple languages like Python, SQL and Java effortlessly, and even allow us to embed documentation with inline Markdown.

* **Accessibility:** notebooks are used across disciplines, making them a familiar tool for data engineers, data scientists and data analysts, lowering the barrier to entry for less technical users and abstracting away complexities like environment and dependency management.

* **Collaboration:** platforms like Databricks offer collaborative notebook experiences, similar to a shared Google doc, meaning multiple team memebers can write and interact with code simultanesouly

All of these things are genuinely positive facets of the notebook experience and in an agile environment where we want to get data into the hands of our users as quickly as possible, things like time-to-value and ease of use are nothing to scoff at. As is often said though, _"there's no such thing as a free lunch"_, and these benefits typically come with some significant tradeoffs:

* **Developer experience:** since most platforms offer a browser-based notebook interface, the physical act of writing code can often be sluggish and frustrating. In addition, the ease of use tends to come at the expense of a feature-incomplete experience, where debugging is hard or impossible, and basic IDE configuration is non-existent.

* **Code structure:** notebooks have historically been geared towards activities like exploratory data analysis or proptotyping and are inherently isolated from a code perspective. Modularising code into re-usable interfaces and components can be difficult, especially in monorepos where the PYTHONPATH configuration can become messy. We're often forced to resort to things like magic `%run` commands and hard-coded relative paths, where "import" becomes slang for eager execution, and namespace conflicts become a genuine risk.

* **Deployability:** we have no real way of turning notebooks into deployable, versioned artifacts. Whereas we might build a Python package into a wheel and promote it through environments, we're often left with little more than a glorified copy and paste deployment pipeline when dealing with notebooks.

* **Code quality:** notebooks are nearly impossible to run through standard code quality checks. Since standard import approaches often don't work or, in the case of some notebooks, code itself is stored in non-Python formats like JSON, linting, formatting, type checking and security checking is often impossible or, at best, overly convoluted and bespoke.

* **Testability:** since the use of notebooks often brings with it a "scripting" mentality to development, we routinely end up with code which is poorly abstracted and difficult to test. When testing _is_ possible, it's almost always difficult to automate, since notebooks couple us tightly to a given development platform, rather than an environment which can be easily replicated as part of continuous integration pipelines.

## Stop writing scripts. Start writing applications

To embrace the _"Stop writing scripts. Start writing applications"_ mantra means a fundamental shift in how we think about our code, focusing on writing well-reasoned, well-abstracted and well-tested data applications, rather than isolated, script-first notebooks. In doing this, we should aim to adopt software engineering best practices gleaned over decades of delivery - after all, data engineering is ultimately a specialised subset of software engineering focused on systems which collect, process and store data. Broadly speaking, all of the keys to successful software delivery are equally applicable to successful data delivery.

### Structuring the project

In general, each data domain or data product (or whatever other logical boundary we choose to define), should constitute a single data application. In practice, a data application will typically take the form of a series of distributed jobs (probably running on Spark, though the specific platform and execution engine are broadly irrelevant). We want to aim for individual jobs to be independent of one another in terms of physical execution, however there will almost certainly be logical dependencies where the output of one job forms the basis for the input to another. For example, when populating a fact in a star schema, we generally need to populate the dimenions first, since foreign key lookups in the fact are inherently dependent on the dimensions. These dependencies should be reflected as part of the orchestration process, rather than being embedded in the application itself.

To make the rest of this discussion more concrete, we'll assume our data application is PySpark-based and focus on that context from now on. To begin, we want to structure our project so that we're able to build a versioned and deployable artifact, as well as make use of the full Python ecosystem. This really just means that we want to structure our project as a standard Python project using a tool like [Poetry](https://python-poetry.org), deploy our project by building a wheel or some other similar artifact, and follow the usual best practices that would be applicable to any other modern Python project, namely:

* Linting and code formatting (e.g., [Ruff](https://docs.astral.sh/ruff/))
* Static type checking (e.g., [Mypy](https://mypy.readthedocs.io/en/stable/))
* Security checking (e.g., [Bandit](https://bandit.readthedocs.io/en/latest/))
* Docstring formatting (e.g., [Docformatter](https://docformatter.readthedocs.io/en/latest/))
* Automated API documentation (e.g., [Pdoc](https://pdoc.dev))
* Unit and interation testing (e.g., [Pytest](https://docs.pytest.org/en/stable/))
* Architectural decision records (e.g., as outlined by [Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions))

> ⚠️ In relation to the ability to deploy data applications through mechanisms like wheels; a data platform's ability to support this as opposed the notebook-based route mentioned above should be a significant indicator as to the maturity of the platform and its suitability as a serious, scalable, development environment.

In terms of a loose project structure, a typical, minimal project for the `foo` domain might look something like this:

```txt
├── config
├── docs
│   ├── api
│   └── decisions
├── src
│   └── foo
│       ├── jobs
│       └── tools
├── .gitignore
├── .pre-commit-config.yaml
├── pyproject.toml
└── README.md
```

### Defining the application boundaries

The term "data application" is purposefully vague but in reality these applications will often take the form of an Extract, Transform, Load (ETL) process. If we think about the typical ETL process that we might commonly want to build on platforms like Databricks or Amazon EMR, then we can really think of the Extract and Load stages as defining the I/O boundaries of our application - it's at these points that we reach out and interact with the world. This fact should inform our overall software design and, in particualr, the way we test the different components of the process:

!["A diagram showing the constituent pieces of an ETL process and the associated testing boundaries"]({{ "/assets/img/stop-writing-scripts-etl.png" | relative_url }})

As outlined in the diagram above, each ETL process should follow the same generic structure where I/O boundaries are isolated from core transformations (i.e., the main business logic) - in general:

1. Reading and writing data should be abstracted into re-usable interfaces that can be easily tested and mocked, and which form a boundary between I/O and core business rules. These interfaces should be subject to their own unit and, crucially, integration tests.

2. The bulk of an ETL process should be constructed from the sequential application of (more or less) pure transformation functions which take one or more data inputs along with any relevant parameters, and return a single data output.

3. For the sake of portability and accesibility, all transformations should be written as SQL `SELECT` statements.

4. Each transformation should form a unit with an associated test, or set of tests when behaviour is complex. Where multiple tests are needed, we should consider using a single parameterized test for clarity.

5. In addition to integration tests for I/O interfaces and unit tests for individual units of transformation, we should also define E2E (end-to-end) integration tests that ensure the entire process runs smoothly and produces the expected outputs given defined inputs.

### Structuring jobs

Using the `foo` domain example from above, each job within the domain should generally be constructed from two pieces:

```txt
src
└── foo
    ├── jobs
    │   └── bar
    │       ├── __init__.py
    │       ├── etl.py
    │       └── transforms.py
```

* `foo.jobs.bar.etl` - forms the basis for ETL orchestration, defining a `run` function which reads from data sources, applies transformations, and writes to the target.
  
* `foo.jobs.bar.transforms` - defines a transforms class whose methods implement individual units of transformation, or equivalent free transform functions.

From a testing perspective, `etl` is typically tested through integration tests, whilst `transforms` is tested via unit tests of the individual transformations.

### Abstracting the I/O components

A useful abstraction when trying to isolate the the I/O components of an ETL process (the E and L), from the transformation component (the T), is through the introduction of a Data Access Layer (DAL) which acts as a lightweight wrapper around read and write operations against a datastore. Let's imagine that we're reading from and writing to tables in a a Unity Catalog metastore in Databricks - what might a simple DAL look like?

```python
from logging import Logger

from pyspark.sql import DataFrame, SparkSession


class UnityCatalog:
    def __init__(self, spark: SparkSession, logger: Logger, catalog: str) -> None:
        self._spark = spark
        self._logger = logger
        self._catalog = catalog

    def read(self, table: str, schema: str, select: list[str] | None = None) -> DataFrame:
        name = f"{schema}.{table}"
        colums = ["*"] if select is None else select
        self._logger.info(f"Reading table '{name}' from catalog '{self._catalog}'")
        return self._spark.read.table(f"{self._catalog}.{name}").select(*colums)

    def append(self, data: DataFrame, table: str, schema: str) -> None:
        name = f"{schema}.{table}"
        self._logger.info(f"Appending records to table '{name}' in catalog '{self._catalog}'")
        data.write.format("delta").mode("append").saveAsTable(f"{self._catalog}.{name}")

```

We can now create catalog-specific instances of the `UnityCatalog` class and use them to interact with data consistently across multiple ETL processes:

```python
import logging

from pyspark.sql import SparkSession

spark = SparkSession.builder.getOrCreate()
logger = logging.getLogger("example")

# Log output:
# [2025-08-13 16:19:52,900 | INFO ] : Rading table 'that.other' from catalog 'this'
this = UnityCatalog(spark, logger, "this")
other = foo.read("other", "that")

```

Alternatively, instead of specifying _what_ datastore we're interacting with (Unity Catalog, SQL Server, Amazon S3 or anything else), we could instead specify _how_ we intract with those datastores:

```python
from typing import Protocol

from pyspark.sql import DataFrame


class HasRead(Protocol):
    def read(self, table: str, schema: str, select: list[str] | None = None) -> DataFrame:
        """Reads a table from the given schema and returns the result as a DataFrame."""


class HasAppend(Protocol):
    def append(self, data: DataFrame, table: str, schema: str) -> None:
        """Appends records from the source DataFrame to the target table."""


def run(foo: HasRead, bar: HasRead, baz: HasAppend) -> None:
    """Orchestrates the ETL process."""

```

Now we don't really care _where_ our data is stored, we just care that wherever it is, that place supports interacting with the data in the way we want. These new type hints tell us that:

* We read data from tables in `foo` and `bar`
* We append data to a table in `baz`

This is more informative than just knowing that, for example, _"`foo` is a Unity Catalog catalog"_. Now, if `foo` was originally stored in a SQL Server database but has been migrated to Unity Catalog, nothing in the ETL code needs to change because all the orchestration code cares about is that the read behaviour is still supported. By modelling these capabilities as separate Protocol types, we avoid forcing every DAL to implement methods it doesn’t actually need. This keeps the contracts small and focused, and means our orchestration logic stays completely agnostic about the actual implementation. That way, `foo`, `bar`, and `baz` could each be:

* Different concrete DALs for different systems
* Mock objects for testing
* Temporary stubs while you migrate from one storage system to another

The orchestration code doesn’t care — it only cares that each object supports the behaviour it needs.

### Enforcing a transformation approach

In the ETL principles above we mentioned that all transformations should be written in the form of SQL `SELECT` statements - this is a matter of preference but if we do want to enforce this, we can again implement a simple abstraction:

```python
from typing import Any

from pyspark.sql import DataFrame, SparkSession


class SparkQueryEngine:
    def __init__(self, spark: SparkSession) -> None:
        self._spark = spark

    def query(self, statement: str, tables: dict[str, DataFrame], params: dict[str, Any] | None = None) -> DataFrame:
        return self._spark.sql(sqlQuery=statement, args=params, **tables)

```

This class looks fairly innocuous but it serves the specific puspose of allowing us to avoid passing around a loose Spark session and instead pass around an abstraction of the Spark session that enforces an agreed methodology to defining transforms. We can now define transforms as follows:

```python
from pyspark.sql import DataFrame


def add_that(engine: SparkQueryEngine, foo: DataFrame, bar: DataFrme, category: str) -> DataFrame:
    return engine.query(
        statement="""
            SELECT f.id, f.this, b.that
            FROM {foo} f
            INNER JOIN {bar} b
            ON f.id = b.id AND b.other = :category
        """,
        tables={"foo": foo, "bar": bar},
        params={"category": category},
    )

```

The benefit of running SparkSQL queries directly on top of DataFrames as above is that we no longer need to worry about setting up temporary views for each of our DataFrames, and we can easily unit test these SQL-based transforms:

```python
import pytest
from pyspark.sql import SparkSession
from pyspark.testing import assertDataFrameEqual

from foo.jobs.bar import transforms


@pytest.fixture(scope="session")
def spark() -> SparkSession:
    return SparkSession.builder.master("local[1]").getOrCreate()


def test_should_add_that(spark: SparkSession) -> None:
    foo = spark.createDataFrame(
        data=[(1, "cat"), (2, "dog"), (3, "fish"), (4, "squirrel")],
        schema="id BIGINT, this STRING",
    )
    bar = spark.createDataFrame(
        data=[(1, "red", "colour"), (2, "green", "colour"), (3, "sunny", "weather")],
        schema="id BIGINT, that STRING, other STRING",
    )

    expected = spark.createDataFrame(
        data=[(1, "cat", "red"), (2, "dog", "green")],
        schema="id BIGINT, this STRING, that STRING",
    )

    actual = transforms.add_that(foo, bar, category="colour")
    assertDataFrameEqual(actual, expected)

```

### The final product

Using the ideas we've outlined above, the `foo` domain's `bar` job would implement an `etl` module that looked something like this:

```python
# src/foo/jobs/bar/etl.py

from logging import Logger

from foo.jobs.bar import transforms
from foo.tools.behaviors import HasAppend, HasRead
from foo.tools.query import SparkQueryEngine


def run(source: HasRead, target: HasAppend, engine: SparkQueryEngine) -> None:
    # Extract
    something = source.read("source_table", "source_schema", select=["first", "second", "third"])

    # Transform
    transformed = transforms.add_this(engine, something)
    transformed = transforms.add_that(engine, transformed)
    transformed = transforms.add_the_other(engine, transformed)

    # Load
    target.append(transformed, "target_table", "target_schema")

```

This approach ensures that:

* Each job is isolated from any other, with the only dependencies being logical dependencies on the data the job needs to read
* All core business rules defined by our transforms are testable in isolation and written in a format which is understandable by a large range of users outside of data engineers
* The overall ETL process is easily testable, either by standing up real instances of required tables or by mocking the DALs that are passed into the `run` function
* The separation of each stage of the ETL process is clear and provides a simple high-level flow of data through the ETL process

Dependng on the similarity of the various jobs in the `foo` domain, we might choose to define a single entrypoint into the application or we might decide to have an entrypoint per job. In either case, the entrypoint is where we would handle instantiating things like a Spark session and instances of our DALs. In addition, we might also want to pass a logger into the `run` function or alternatively define some kind of decorator for transforms to auto-log key execution metrics to avoid cluttering the `run` function.