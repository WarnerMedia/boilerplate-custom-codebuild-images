# Lambda Trunk-Based Deployment (v1)

## Table of Contents

- [Folder Structure](#folder-structure)
- [Install/Initial Setup](#installinitial-setup)
- [Version Management](#version-management)

# Folder Structure

This section describes the layout of the `v1` version of this project.

- [`env`](env): Any environment-related override files.
    * There are a number of JSON files in this folder which are used to override parameters in the various CloudFormation templates (via CodePipeline CloudFormation stages).  This is very useful for making specific changes to different environments.
    * This folder could also contain other environment configuration files for the application itself.
- [`iac`](iac): Any infrastructure-as-code (IaC) templates.
    * Currently this only contains CloudFormation YAML templates.
    * The templates are categorized by AWS service to try to make finding and updated infrastructure easy.
    * This folder could also contain templates for other IaC solutions.
- [`node_modules`](node_modules): Node.js modules that the Lambda(s) need to function.  This folder will only exist if there are modules that the Lambda function needs.
- [`src`](src): The source files needed for the function (sans the `node_modules` folder).
    * You could house the source code for multiple related functions in this folder if this project has multiple functions to deploy.
- [`version root`](./): All of the files that are generally designed to be at the base of the project.
    * Node.js `package.json`, `package-lock.json` and CodePipeline `version.json` file.
    * Miscellaneous files, such as the version `README.md` file.

# Install/Initial Setup

---
**NOTE**

These setup instructions assume you have already set up the base infrastructure: [boilerplate-aws-account-setup](https://github.com/warnermedia/boilerplate-aws-account-setup)

The `boilerplate-aws-account-setup` repository will get cloned (uisng the "Use this template" button) for each set of accounts; this allows for base infrastructure changes that are specific to that account.  Then changes can be made without impacting the original boilerplate repository.

---

## Prerequisite Setup

### GitHub User Connection (if a private repository)

1. This repository is meant to be used as a starting template, so please make use of the "Use this template" button in the GitHub console to create your own copy of this repository.
2. Since you have the base infrastructure in place, in your primary region, there should be an SSM parameter named: `/account/main/github/service/username`
3. This should be the name of the GitHub service account that was created for use with your AWS account.
4. You will want to add this service account user to your new repository (since the repository is likely private, this is required).
5. During the initial setup, the GitHub service account will need to be given admin. access so that it can create the needed webhook (no other access level can create webhooks at this time).

## Primary Setup (AWS Console)

1. You will want to make a local checkout of the repository that you created.
2. Once you have the local checkout, switch to the `v1` folder.
3. Find the following CloudFormation template: [`iac/cfn/codepipeline/deploy.yaml`](iac/cfn/codepipeline/deploy.yaml)
4. Log into the AWS Console for your account in your primary region.
5. Go to the CloudFormation console.
6. Upload this template and then fill in all of the needed parameter values.
7. Go through all the other CloudFormation screens and then launch the stack.
8. Monitor the stack and make sure that it completes successfully.

# Version Management

The version of the application can only be managed manually for this simple flow.

---
**NOTE**

Semantic versioning should be used for maintaining the version of this application.  If the same versioning method is used between applications, it is helpful for consistency.

[Semantic Versioning](https://semver.org)

Given a version number `MAJOR.MINOR.PATCH`, increment the:

- `MAJOR` version when you make incompatible API changes,
- `MINOR` version when you add functionality in a backwards compatible manner, and
- `PATCH` version when you make backwards compatible bug fixes.
- Additional labels for pre-release and build metadata are available as extensions to the `MAJOR.MINOR.PATCH` format.

---

## Manual Version Update

Since this is a Node.js application, the `package.json` file manages the version number for the application.  However, AWS CodePipeline can only read from a flat JSON file.  Because of this, there is a simple `version.json` file, which can be used to manage the version of the repository.

1. Once you have your changes ready to commit to your `bugfix`/`feature` branch, review the changes and see which semantic versioning level they match up with.
2. Open the `package.json` file.
3. Update the the `version` property in the JSON object to the needed value.
4. Open the `version.json` file.
5. Update the the `version` property in the JSON object to the needed value.
6. Commit these version updates with the rest of your changes.
7. Merge your pull request into the `main` branch.
8. The AWS CodePipeline will notice that you manually updated the version number and will use your version number.