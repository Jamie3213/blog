+++
author = "Jamie Hargreaves"
title = "Static Blogging with AWS"
date = "2022-01-11"
description = "Deploying a static blog using Hugo and AWS."
tags = [
    "aws",
    "amazon s3",
    "amazon cloudfront",
    "amazon route 53",
    "aws codebuild",
    "aws eventbridge",
    "hugo",
    "markdown"
]
draft = "true"
+++

## Overview

This post walks through the process of building and deploying a static blog (or any static website, for that matter), using [Hugo](https://gohugo.io), and AWS services like Amazon S3 and CloudFront. In addition, it shows how to utilise [Terraform](https://www.terraform.io) to deploy the necessary AWS resources as code, along with a walk-through of an automated CI/CD pipeline using AWS CodeBuild for deploying new posts or changes to the website.

Before we get into things, you can find the full source code for this blog [on GitHub](https://github.com/Jamie3213/blog).

## Defining the Solution

We've established that we're going to build a blog or some other website, but the key here is that we're building a *static* site, i.e. we're building a site that doesn't have dynamic content which means that it doesn't utilise server-side processing to do things like calling REST APIs or interacting with databases - once we've written our content, it doesn't change and it doesn't need to rely on any external resources. Whilst this is restrictive for some things (you wouldn't want your e-commerce site to be static, for example), it's perfect for a blog and it means that despite the fact that I know very little about good web development, I can very quickly build an aesthetically pleasing blog with minimal effort.

In addition to being much easier to build, the fact our site is static means it'll also be much easier (and cheaper), to host. For hosting, we're going to utilise Amazon S3, a cloud object store that supports servicing static web content, and Amazon CloudFront, a Content Delivery Network (CDN). Whilst not strictly necessary, the use of a CDN lets us cache our static content on AWS edge nodes for better end-user performance, rather than making our users go all the way to S3 every time and, since it's very cheap for our use case, we'll use it - if you're interested, you can read more about how CloudFront handles requests in the [documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/HowCloudFrontWorks.html).

Overall, our solution architecture is fairly straight forward and is going to look like the diagram below, and we'll discuss each component as we go.

!["Blog Solution Architecture Diagram"](/images/BlogSolutionArchitecture.png)

## The Blog Itself

### Choosing a Framework

Okay, so we've seen the overall solution, but the first question is how am I going to build the actual blog? Well, there are numerous options and for a while I toyed around with the idea of building a custom site in [React.js](https://reactjs.org) (and actually made a start on it), however as I was doing so I realised two things:

* Firstly, web-development isn't my forté; I know enough JavaScript to get by, but when it comes to responsive design and all the other intricacies of building a site that will reliably work across a range of devices, I'm out of my depth.
* Secondly, whilst building your own React application (or using any number of other frameworks like Next.js or AngularJS), is a great way to learn more about web development, it's also fairly time consuming if you're new to it and I found it detracted from the purpose of the project, which was to start a blog, not to learn web development.

As such, if you're mostly interested in quickly getting something up and running and actually starting to add content to your blog, I'd recommend the option I ultimately went with: Hugo. Hugo is an open-source web framework specifically designed with static web content in mind and with tons of community support for responsive themes which makes development extremely easy, even if (like me), you've little to no web development experience.

### Building the Blog
