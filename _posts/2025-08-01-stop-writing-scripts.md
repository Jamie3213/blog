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

One of my biggest frustrations with data engineering, both the discipline itself and the platforms that support it (like Databricks and Microsoft Fabric), is the seemingly constant, never-ending push towards notebooks as the primary mechanism to write and deliver code. Before we discuss what's _bad_ about notebooks though, let's think about why they might have become so popular:

* **Time-to-value:** notebooks take us from zero to _something_ quickly, they let us write code and interact with data with little to no setup, often inside the browser.

* **Versatility:** notebooks let us flit between multiple languages like Python, SQL and Java effortlessly, and even allow us to embed documentation with inline Markdown.

* **Accessibility:** notebooks are used across disciplines, making them a familiar tool for data engineers, data scientists and data analysts, lowering the barrier to entry for less technical users.

* **Collaboration:** platforms like Databricks offer collaborative notebook experiences, similar to something like a shared Google doc, meaning multiple team memebers can write and interact with a piece of code simultaneously.

All of the things we've listed above are genuinely positive facets of the notebook experience and in an agile environment where we want to get data into the hands of our users as quickly as possible, things like time-to-value and ease of use are nothing to scoff at. As is often said though, _"there's no such thing as a free lunch"_, and these benefits typically come with some significant tradeoffs:

* **Developer experience:** since most platforms offer a browser-based notebook interface, the physical act of writing code can often be sluggish and frustrating. In addition, the ease of use tends to come at the expense of a feature-incomplete experience, where debugging is hard or impossible, and basic IDE configuration is non-existent.

* **Code structure:** notebooks were historically geared towards activities like exploratory data analysis or proptotyping and are inherently isolated from a code perspective. Modularising code into re-usable interfaces and components can be difficult, especially in monorepos where the PYTHONPATH configuration can be messy. We're often forced to resort to things like magic `%run` commands where all our imported code is eagerly executed and namespace conflicts become a genuine risk.

* **Deployability:** we have no real way of turning a notebook (or set of notebooks) into a deployable, versioned artifact. Whereas we might build a Python package into wheel and promote it through environments, we're often left with little more than a copy and paste deployment pipeline when dealing with notebooks.

* **Code quality:** notebooks are nearly impossible to run through standard code quality checks. Since standard import approaches often don't work or, in the case of some notebooks, code itself is stored in non-Python formats like JSON, linting, formatting, type checking and security checking is often impossible or, at best, overly convoluted and bespoke.

* **Testability:** since the use of notebooks often brings with it a "scripting" mentality to development, we routinely end up with code which is poorly abstracted and difficult to test. When testing _is_ possible, it's almost always difficult to automate, since notebooks couple us tightly to a given development platform, rather than a repoducible local environment which can be easily replicated as part of continuous integration pipelines.

## What does heaven look like?

Heaven might be a bit of a stretch and whilst _"stop writing scripts, start writing applications"_ is a good mantra, what does it mean in practice? To begin with, we need a fundamental shift in how we think about code, focusing on writing well-reasoned, well-abstracted and well-tested data applications, rather than isolated, script-style notebooks. In doing this, we should aim to adopt all of the usual best practices developed over years in the field of software engineering. Data engineering is ultimately a specialised subset of software engineering focused on systems which collect, process and store data. Broadly speaking, all of the keys to successful software delivery are equally valid in, and equally applicable to, successful data delivery.
