---
layout: post
author: Jamie Hargreaves
title: Stop Writing Scripts, Start Writing Applications
date: 2025-08-01
permalink: /blog/stop-writing-scripts-start-writing-applications
tags: python spark etl
---

![Header showing a picture of a mountain range]({{ "/assets/img/pragmatic-fp-header.jpg" | relative_url }})

* TOC
{:toc}

## I've been to hell and it looks like a Jupyter notebook

One of my biggest frustrations with data engineering, both the discipline itself and the platforms that support it (like Databricks and Microsoft Fabric), is the relentless and seemingly never-ending push towards notebooks as the primary mechanism to write and deliver code. Before we discuss what's _bad_ about notebooks though, let's think about why they might have become so popular and why enterprise platforms seem so intent on ecouraging their use:

* **Time-to-value:** notebooks take us from zero to _something_ quickly, they let us write code and interact with data with little to no setup, often inside the browser.

* **Versatility:** notebooks let us flit between multiple languages like Python, SQL and Java effortlessly, and even allow us to embed documentation with inline Markdown.

* **Accessibility:** notebooks are used across disciplines, making them a familiar tool for data engineers, data scientists and data analysts, lowering the barrier to entry for less technical users and abstracting away complexities like environment and dependency management.

* **Collaboration:** platforms like Databricks offer collaborative notebook experiences, similar to something like a shared Google doc, meaning multiple team memebers can write and interact with a piece of code simultaneously.

These things are all genuinely positive facets of the notebook experience and in an agile environment where we want to get data into the hands of our users as quickly as possible, things like time-to-value and ease of use are nothing to scoff at. As is often said though, _"there's no such thing as a free lunch"_, and these benefits typically come with some significant tradeoffs:

* **Developer experience:** since most platforms offer a browser-based notebook interface, the physical act of writing code can often be sluggish and frustrating. In addition, the ease of use tends to come at the expense of a feature-incomplete experience, where debugging is hard or impossible, and basic IDE configuration is non-existent.

* **Code structure:** notebooks have historically been geared towards activities like exploratory data analysis or proptotyping and are inherently isolated from a code perspective. Modularising code into re-usable interfaces and components can be difficult, especially in monorepos where the PYTHONPATH configuration can become messy. We're often forced to resort to things like magic `%run` commands and hard-coded relative paths, where "import" becomes slang for eager execution, and namespace conflicts become a genuine risk.

* **Deployability:** we have no real way of turning notebooks into deployable, versioned artifacts. Whereas we might build a Python package into a wheel and promote it through environments, we're often left with little more than a glorified copy and paste deployment pipeline when dealing with notebooks.

* **Code quality:** notebooks are nearly impossible to run through standard code quality checks. Since standard import approaches often don't work or, in the case of some notebooks, code itself is stored in non-Python formats like JSON, linting, formatting, type checking and security checking is often impossible or, at best, overly convoluted and bespoke.

* **Testability:** since the use of notebooks often brings with it a "scripting" mentality to development, we routinely end up with code which is poorly abstracted and difficult to test. When testing _is_ possible, it's almost always difficult to automate, since notebooks couple us tightly to a given development platform, rather than an environment which can be easily replicated as part of continuous integration pipelines.

## What does heaven look like?

Heaven might be a bit of a stretch and whilst _"stop writing scripts, start writing applications"_ might sound catchy, what does it mean in practice? To begin with, we need a fundamental shift in how we think about code, focusing on writing well-reasoned, well-abstracted and well-tested data applications, rather than isolated, script-first notebooks. In doing this, we should aim to adopt all of the usual best practices and learnings gleaned over years in the field of software engineering. Data engineering is ultimately a specialised subset of software engineering focused on systems which collect, process and store data. Broadly speaking, all of the keys to successful software delivery are equally valid in (and applicable to), successful data delivery.

### Structuring a project

In general, each data domain or data product (or whatever other philosophy we choose to adopt), should define its own set of data applications - in practice, each application will typically take the form of a Spark process, although the specific execution engine and platform is broadly irrelevant. Whilst we want to aim for applications to be independent of one another in terms of physical execution, there'll typically be logical dependencies in terms of the outputs of one job forming the basis for the input to another. For example, when populating a fact in a star schema, we generally need to populate the dimenions first, since foreign key lookups in the fact are inherently dependent on them. These dependencies can be reflected as part of the orchestration process, rather than being embedded in the applications themselves.

Thinking particularly about PySpark-based data applications, we want to structure our project such that we're able to build a versioned and deployable artifact, as well as make use of the full Python ecosystem. This really just means that we want to structure our project as a standard Python project using a tool like [Poetry](https://python-poetry.org), deploy our project by building a wheel or some other similar artifact, and follow the usual best practices that would be applicable to any other modern Python project, namely:

* Linting and code formatting (e.g., [Ruff](https://docs.astral.sh/ruff/))
* Static type checking (e.g., [Mypy](https://mypy.readthedocs.io/en/stable/))
* Security checking (e.g., [Bandit](https://bandit.readthedocs.io/en/latest/))
* Docstring formatting (e.g., [Docformatter](https://docformatter.readthedocs.io/en/latest/))
* Automated API documentation (e.g., [Pdoc](https://pdoc.dev))
* Unit and interation testing (e.g., [Pytest](https://docs.pytest.org/en/stable/))
* Architectural decision records (e.g., as outlined by [Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions))

In relation to the ability to deploy data applications through mechanisms like wheels; a data platform's ability to support this as opposed the notebook-based route mentioned above should be a significant indicator as to the maturity of the platform and its suitability as a serious, scalable, development platform.

In terms of a loose project structure, a typical, minimal project for the `foo` domain might look something like this:

```txt
├── config
├── docs
│   ├── api
│   └── decisions
├── src
│   └── foo
│       ├── jobs
│       └── utils
├── .gitignore
├── .pre-commit-config.yaml
├── pyproject.toml
└── README.md
```

### Defining the testing boundaries

The term "data application" is purposefully vague but in reality these applications will often utlimately take the form of an Extract, Transform, Load (ETL) process. If we think about the typical ETL process that we might commonly want to build on platforms like Databricks or EMR, then we can really think of the Extract and Load stages as defining the I/O boundaries of our application - it's at these points that we reach out and interact with the world. This fact should inform our overall software design and, in particualr, the way we test the different components of the process:

!["A diagram showing the constituent pieces of an ETL process and the associated testing boundaries"]({{ "/assets/img/stop-writing-scripts-etl.png" | relative_url }})

As outlined in the diagram above, each ETL process should follow the same generic structure where I/O boundaries are isolated from core transformations (i.e., the main business logic). In general:

1. Reading and writing data should be abstracted into re-usable interfaces that can be easily tested and mocked, and which form a boundary between I/O and core business rules. These interfaces should be subject to their own unit and, crucially, integration tests.

2. The bulk of an ETL process should be constructed from the sequential application of "pure" transformation functions which take one or more data inputs along with any relevant parameters, and return a single data output.

3. For the sake of portability and accesibility, all transformations should be written as SQL `SELECT` statements.

4. Each transformation forms a unit which should have an associated test or set of tests when behaviour is complex. Where multiple tests are needed, consider using a single parameterized test for clarity.

5. In addition to integration tests for I/O interfaces and unit tests for individual units of transformation, we should also define E2E (end-to-end) integration tests that ensure the entire process runs smoothly and produces the expected outputs given defined inputs.

### Code Structure

Using the `foo` domain example from above, each job within the domain should generally be constructed from two pieces:

```txt
src
└── foo
    ├── jobs
    │   └── bar
    │       ├── __init__.py
    │       ├── etl.py
    │       └── transformer.py
```

* `foo.jobs.bar.etl` - forms the basis for ETL orchestration, defining a `run` function which reads data, applies transformations, and writes to the target.
  
* `foo.jobs.bar.transformer` - defines a transformer class whose methods implement individual units of transformation, or equivalent free functions.

From a testing perspective, `etl` is typically tested through integration tests, whilst `transformer` is tested via unit tests of the individual transformations.
