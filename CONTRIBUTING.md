# Contributing to Fast MCP

Thank you for your interest in contributing to Fast MCP! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Contributing to Fast MCP](#contributing-to-fast-mcp)
  - [Table of Contents](#table-of-contents)
  - [Code of Conduct](#code-of-conduct)
  - [Getting Started](#getting-started)
    - [Development Environment](#development-environment)
    - [Running Tests](#running-tests)
  - [How to Contribute](#how-to-contribute)
    - [Reporting Bugs](#reporting-bugs)
    - [Suggesting Enhancements](#suggesting-enhancements)
    - [Pull Requests](#pull-requests)
  - [Style Guidelines](#style-guidelines)
    - [Code Style](#code-style)
    - [Commit Messages](#commit-messages)
    - [Documentation](#documentation)
  - [Development Process](#development-process)
    - [Branching Strategy](#branching-strategy)
    - [Release Process](#release-process)
  - [Community](#community)
  - [Legal](#legal)

## Code of Conduct

This project and everyone participating in it is governed by the [Fast MCP Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

### Development Environment

To set up your development environment:

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/yjacquin/fast-mcp.git
   cd fast-mcp
   ```
3. Install dependencies:
   ```bash
   bundle install
   ```
4. Run the tests to make sure everything is working:
   ```bash
   bundle exec rspec
   ```

### Running Tests

Fast MCP uses RSpec for testing. To run the tests:

```bash
bundle exec rspec
```

To run a specific test file:

```bash
bundle exec rspec spec/path/to/file_spec.rb
```

## How to Contribute

### Reporting Bugs

If you find a bug, please report it by creating an issue on GitHub. When filing a bug report, please include:

- A clear, descriptive title
- A detailed description of the issue, including steps to reproduce
- The expected behavior and what actually happened
- Any relevant logs or error messages
- Your Ruby version and operating system
- Any other context that might be helpful

### Suggesting Enhancements

If you have an idea for an enhancement or a new feature, please create an issue on GitHub. When suggesting an enhancement, please include:

- A clear, descriptive title
- A detailed description of the proposed enhancement
- The motivation for the enhancement (why it would be useful)
- Any examples of how the enhancement would work
- Any relevant references or resources

### Pull Requests

1. Create a new branch for your changes:
   ```bash
   git checkout -b my-feature-branch
   ```
2. Make your changes and commit them with clear, descriptive commit messages
3. Add or update tests as necessary
4. Update documentation as necessary
5. Push your branch to your fork:
   ```bash
   git push origin my-feature-branch
   ```
6. Create a pull request from your branch to the main repository
7. Describe your changes in the pull request description
8. Link to any related issues

Pull requests should:

- Address a single concern
- Include tests for new functionality
- Update documentation as necessary
- Follow the style guidelines
- Pass all tests and CI checks

## Style Guidelines

### Code Style

Fast MCP follows the [Ruby Style Guide](https://rubystyle.guide/). We use Rubocop to enforce these guidelines. To check your code:

```bash
bundle exec rubocop
```

To automatically fix some issues:

```bash
bundle exec rubocop -a
```

### Commit Messages

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line
- Consider starting the commit message with an applicable emoji:
  - ✨ `:sparkles:` when adding a new feature
  - 🐛 `:bug:` when fixing a bug
  - 📚 `:books:` when adding or updating documentation
  - ♻️ `:recycle:` when refactoring code
  - 🧪 `:test_tube:` when adding or updating tests
  - 🔧 `:wrench:` when updating configuration files

### Documentation

- Use [YARD](https://yardoc.org/) for code documentation
- Update the README.md and other documentation as necessary
- Add examples for new features
- Keep documentation up-to-date with code changes

## Development Process

### Branching Strategy

- `main` is the default branch and should always be deployable
- Feature branches should be created from `main` and merged back via pull requests
- Release branches are created for each release and named `release/vX.Y.Z`
- Hotfix branches are created from the release branch and named `hotfix/vX.Y.Z.N`

### Release Process

1. Update the version number in `lib/mcp/version.rb`
2. Update the CHANGELOG.md with the changes in the new version
3. Create a release branch `release/vX.Y.Z`
4. Create a pull request to merge the release branch into `main`
5. After the pull request is merged, create a new release on GitHub
6. Build and publish the gem to RubyGems

## Community

- Join the discussion on [GitHub Discussions](https://github.com/yourusername/fast-mcp/discussions)
- Follow the project on social media (if applicable)
- Participate in community events and meetups

## Legal

By contributing to Fast MCP, you agree that your contributions will be licensed under the project's MIT license.

Thank you for contributing to Fast MCP!
