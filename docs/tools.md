# Working with MCP Tools

Tools are a core concept in the Model Context Protocol (MCP). They allow you to define functions that can be called by clients, including AI models. This guide covers everything you need to know about defining, using, and extending tools in Fast MCP.

## Table of Contents

- [What are MCP Tools?](#what-are-mcp-tools)
- [Defining Tools](#defining-tools)
  - [Basic Tool Definition](#basic-tool-definition)
  - [Tool Arguments](#tool-arguments)
  - [Argument Types](#argument-types)
  - [Argument Validation](#argument-validation)
  - [Default Values](#default-values)
- [Calling Tools From Another Tool](#calling-tools-from-another-tool)
- [Advanced Tool Features](#advanced-tool-features)
  - [Tool Annotations](#tool-annotations)
  - [Tool Hidden Arguments](#tool-hidden-arguments)
  - [Tool Categories](#tool-categories)
  - [Tool Metadata](#tool-metadata)
  - [Tool Permissions](#tool-permissions)
  - [Request Headers](#request-headers)
  - [Composing Tool Authentication](#composing-tool-authentication)
- [Best Practices](#best-practices)
- [Examples](#examples)

## What are MCP Tools?

MCP Tools are functions that can be called by clients with arguments and return results. They are defined on the server side and can be discovered and called by clients. Tools can:

- Perform calculations
- Access and modify resources
- Interact with external systems
- Call other tools
- Return structured data

Tools are particularly useful for AI models, as they provide a way for models to perform actions in the real world.

## Defining Tools

### Basic Tool Definition

To define a tool, create a class that inherits from `FastMcp::Tool`:

```ruby
class HelloTool < FastMcp::Tool
  description "Say hello to someone"

  def call(**_args)
    "Hello, world!"
  end
end

# Create a server
server = FastMcp::Server.new(name: 'example-server', version: '1.0.0')

# Register the tool with the server
server.register_tool(HelloTool)
```

When defining a tool class, you can:

- Set a description using the `description` class method
- Define arguments using the `arguments` class method with Dry::Schema
- Implement the functionality in the `call` instance method

### Tool Arguments

To define arguments for a tool, use the `arguments` class method with a block using Dry::Schema syntax:

```ruby
class GreetTool < FastMcp::Tool
  description "Greet a person"

  arguments do
    required(:name).filled(:string).description("Name of the person")
  end

  def call(name:)
    "Hello, #{name}!"
  end
end

# Register the tool
server.register_tool(GreetTool)
```

The `arguments` method takes a block where you can define:

- Required arguments using the `required` method
- Optional arguments using the `optional` method
- Types and validations for each argument
- Descriptions for each argument

### Argument Types

Fast MCP supports the following argument types using Dry::Schema predicates:

- `:string`: A string value
- `:integer`: An integer value
- `:float`: A floating-point number
- `:bool`: A boolean value (true/false)
- `:array`: An array of values
- `:hash`: A hash/object with key-value pairs

Example with different types:

```ruby
class ProcessDataTool < FastMcp::Tool
  description "Process various types of data"

  arguments do
    required(:text).filled(:string).description("Text to process")
    optional(:count).filled(:integer).description("Number of times to process")
    optional(:factor).filled(:float).description("Multiplication factor")
    optional(:verbose).filled(:bool).description("Whether to output verbose logs")
    optional(:tags).array(:string).description("Tags to apply")
    optional(:metadata).hash.description("Additional metadata")
  end

  def call(text:, count: 1, factor: 1.0, verbose: false, tags: [], metadata: {})
    # Implementation
    result = text * count
    result = result * factor if factor != 1.0

    if verbose
      {
        result: result,
        tags: tags,
        metadata: metadata
      }
    else
      result
    end
  end
end
```

### Argument Validation

Fast MCP automatically validates arguments based on the Dry::Schema definition. If validation fails, an error is returned to the client.

You can also add custom validation in the `call` method:

```ruby
class DivideTool < FastMcp::Tool
  description "Divide two numbers"

  arguments do
    required(:dividend).filled(:float).description("Number to be divided")
    required(:divisor).filled(:float).description("Number to divide by")
  end

  def call(dividend:, divisor:)
    # Custom validation
    raise "Cannot divide by zero" if divisor == 0

    dividend / divisor
  end
end
```

### Default Values

You can specify default values in the method parameters of the `call` method:

```ruby
class RepeatTool < FastMcp::Tool
  description "Repeat a string multiple times"

  arguments do
    required(:text).filled(:string).description("Text to repeat")
    optional(:count).filled(:integer).description("Number of times to repeat")
  end

  def call(text:, count: 3)
    text * count
  end
end
```

### Authentication and Authorization

Using [the `headers` method](#request-headers), you can access headers passed to the tool call. This can be used to identify a user by authentication details passed in headers:
```ruby
class CurrentUserTool < FastMcp::Tool
  description "Gets the current user details"

  def call
    JSON.generate current_user
  end

  private

  def current_user
    token = headers["AUTHORIZATION"]

    # Validate token
    # ...

    user
  end
end
```

This can be combined with the `authorize` method to ensure a user is authorized before allowing them to use the tool:

```ruby
class PerformAuthenticatedActionTool < FastMcp::Tool
  description "Perform an action which requires an authenticated user"

  arguments do
    required(:item_id).filled(:integer).description('ID of item to affect')
  end

  authorize do |item_id:|
    current_user&.is_admin? &&
      get_item(item_id).user_id == current_user.id
  end

  def call(item_id:)
    # Perform action
    # ...
  end

  private

  def current_user
    # Get current user
    # ...
  end

  def get_item(id)
    # Get item
    # ...
  end
end
```

You can also implement this in a parent class and the authorization will be inherited by all children. Children may also define their own authorization - in this case, _all_ authorization checks must pass for a caller to be allowed access to the tool.

## Calling Tools From Another Tool
Tools can call other tools:

```ruby

class GreetTool < FastMcp::Tool
  description 'Greet one person'

  arguments do
    required(:names).array(:string).description("Name of person to greet")
  end

  def call(name:)
    "Hey #{name}"
  end
end

class GreetMultipleTool < FastMcp::Tool
  description "Greet multiple people"

  arguments do
    required(:names).array(:string).description("Names of people to greet")
  end

  def call(names:)
    raise "Server not set" unless self.class.server

    greet_tool = GreetTool.new
    results = names.map do |name|
      # Call the tool
      greet_tool.call(name: name)
    end

    results.join("\n")
  end
end
```

## Advanced Tool Features

### Tool Annotations

Tool annotations provide additional metadata about a tool's behavior, helping clients understand how to present and manage tools. These annotations are hints that describe the nature and impact of a tool.

```ruby
class WebSearchTool < FastMcp::Tool
  description 'Search the web for information'
  
  annotations(
    title: 'Web Search',           # Human-readable title for the tool
    readOnlyHint: true,           # Indicates the tool doesn't modify its environment
    openWorldHint: true           # The tool interacts with external entities
  )
  
  arguments do
    required(:query).filled(:string).description('Search query')
  end
  
  def call(query:)
    "Searching for: #{query}"
  end
end
```

Available annotations:

| Annotation | Type | Default | Description |
|------------|------|---------|-------------|
| `title` | string | - | A human-readable title for the tool, useful for UI display |
| `readOnlyHint` | boolean | false | If true, indicates the tool does not modify its environment |
| `destructiveHint` | boolean | true | If true, the tool may perform destructive updates (only meaningful when `readOnlyHint` is false) |
| `idempotentHint` | boolean | false | If true, calling the tool repeatedly with the same arguments has no additional effect |
| `openWorldHint` | boolean | true | If true, the tool may interact with an "open world" of external entities |

Example with all annotations:

```ruby
class DeleteFileTool < FastMcp::Tool
  description 'Delete a file from the filesystem'
  
  annotations(
    title: 'Delete File',
    readOnlyHint: false,      # This tool modifies the filesystem
    destructiveHint: true,    # Deleting files is destructive
    idempotentHint: true,     # Deleting the same file twice has no additional effect
    openWorldHint: false      # Only interacts with the local filesystem
  )
  
  arguments do
    required(:path).filled(:string).description('File path to delete')
  end
  
  def call(path:)
    File.delete(path) if File.exist?(path)
    "File deleted: #{path}"
  end
end
```

**Important**: Annotations are hints and not guaranteed to provide a faithful description of tool behavior. Clients should never make security-critical decisions based solely on annotations.

### Tool hidden arguments
If need be, we can register arguments that won't show up in the tools/list call but can still be used in the tool when provided.
This might be useful when calling from another tool, or when the client is made aware of this argument from the context.

```ruby
class AddUserTool < FastMcp::Tool
  description 'Add a new user'
  tool_name 'add_user'
  arguments do
    required(:name).filled(:string).description("User's name")
    required(:email).filled(:string).description("User's email")
    optional(:admin).maybe(:bool).hidden
  end

  def call(name:, email:, admin: nil)
    # Create the new user
    new_user = { name: name, email: email }

    new_user[:admin] = admin if admin

    new_user
  end
end
```

The .hidden predicate takes a boolean value as argument, meaning that it can be variabilized depending on your custom logic. Useful for feature-flagging arguments.

```ruby
class AddUserTool < FastMcp::Tool
  description 'Add a new user'
  tool_name 'add_user'
  arguments do
    required(:name).filled(:string).description("User's name")
    required(:email).filled(:string).description("User's email")
    optional(:admin).maybe(:bool).hidden(!ENV['FEATURE_FLAG'] == 'true')
  end

  def call(name:, email:, admin: nil)
    # Create the new user
    new_user = { name: name, email: email }

    new_user[:admin] = admin if admin

    new_user
  end
end
```

### Tool Categories

You can organize tools into categories using instance variables or metadata:

```ruby
class AddTool < FastMcp::Tool
  description "Add two numbers"

  class << self
    attr_accessor :category
  end

  self.category = "Math"

  arguments do
    required(:a).filled(:float).description("First number")
    required(:b).filled(:float).description("Second number")
  end

  def call(a:, b:)
    a + b
  end
end

class SubtractTool < FastMcp::Tool
  description "Subtract two numbers"

  class << self
    attr_accessor :category
  end

  self.category = "Math"

  arguments do
    required(:a).filled(:float).description("First number")
    required(:b).filled(:float).description("Second number")
  end

  def call(a:, b:)
    a - b
  end
end
```

### Tool Metadata

You can add metadata to tools using class methods:

### Metadata
MCP specifies that we can declare metadata in the tool call result. For this, we have a _meta attr_accessor in all tools. We kept the _meta original naming to avoid collisions with arguments that could be named "metadata". It is a hash that accepts modifications and will be returned to the tool call response whenever it has been modified.

```ruby
class RepeatTool < FastMcp::Tool
  description "Repeat a string multiple times"

  arguments do
    required(:text).filled(:string).description("Text to repeat")
    optional(:count).filled(:integer).description("Number of times to repeat")
  end

  def call(text:, count: 3)
    _meta[:foo] = 'bar'
    _meta[:some_key] = 'some value'

    text * count
  end
end
```

### Tool Permissions

You can implement permission checks:

```ruby
class AdminActionTool < FastMcp::Tool
  description "Perform an admin action"

  class << self
    attr_accessor :required_permission
  end

  self.required_permission = :admin

  arguments do
    required(:action).filled(:string).description("Action to perform")
    required(:user_role).filled(:string).description("Role of the user making the request")
  end

  def call(action:, user_role:)
    # Check permissions
    raise "Permission denied: admin role required" unless user_role == "admin"

    # Perform the action
    "Admin action '#{action}' performed successfully"
  end
end
```

### Request Headers

When using the Rack transport, HTTP headers from tool call requests are exposed to tools via the `headers` method:

```ruby
class MyTool < FastMcp::Tool
  def call
    "Host header is #{headers["HOST"]}"
  end
end
```

### Composing Tool Authentication

It can be useful to extract authentication into modules to share functionality without having to bake logic into your tool's ancestor chain.

```ruby
# This module adds a current_user method to tools which include it, and requires that the user is present
module UserAuthenticator
  def self.included(tool)
    tool.authorize do
      not current_user.nil?
    end
  end

  def current_user
    # Get current user
    # ...
  end
end

# This module ensures that the THIRD_PARTY_API_KEY header is set
module ThirdPartyApiKeyRequired
  def self.included(tool)
    tool.authorize do
      not headers['THIRD_PARTY_API_KEY'].nil?
    end
  end
end

class MyTool < FastMcp::Tool
  # Extra authentications are executed in the order they appear in the tool.
  # In this case:
  # - Any authorizations from ancestor classes
  # - UserAuthenticator
  # - This tool's authorize call
  # - ThirdParyApiKeyRequired
  include UserAuthenticator

  authorize do
    # My custom auth for this tool
    # ...
  end

  include ThirdPartyApiKeyRequired
end
```

## Best Practices

Here are some best practices for working with MCP tools:

1. **Use Clear Names**: Give your tools clear, descriptive names that indicate their purpose.
2. **Provide Good Descriptions**: Write detailed descriptions for tools and their arguments.
3. **Validate Inputs**: Use the schema validation to ensure inputs are correct before processing.
4. **Handle Errors Gracefully**: Catch and handle errors properly, providing clear error messages.
5. **Return Structured Data**: Return structured data when appropriate, especially for complex results.
6. **Test Your Tools**: Write tests for your tools to ensure they work correctly.
7. **Document Usage**: Document how to use your tools, including examples.
8. **Keep Tools Focused**: Each tool should do one thing well, rather than trying to do too much.

## Examples

Here's a more complex example of a tool that interacts with resources:

```ruby
class IncrementCounterTool < FastMcp::Tool
  description "Increment a counter resource"

  # Class variable to hold server instance
  @server = nil

  # Class methods to get and set server instance
  class << self
    attr_accessor :server
  end

  arguments do
    optional(:amount).filled(:integer).description("Amount to increment by")
  end

  def call(amount: 1)
    raise "Server not set" unless self.class.server

    # Get the counter resource
    counter_resource = self.class.server.resources["counter"]
    raise "Counter resource not found" unless counter_resource

    # Parse the current value
    current_value = counter_resource.content.to_i

    # Increment the counter
    new_value = current_value + amount

    # Update the resource
    counter_resource.update_content(new_value.to_s)

    # Return the new value
    { previous_value: current_value, new_value: new_value, amount: amount }
  end
end

# Set the server reference
IncrementCounterTool.server = server

# Register the tool
server.register_tool(IncrementCounterTool)
```

This tool increments a counter resource by a specified amount (or by 1 by default) and returns the previous and new values.
