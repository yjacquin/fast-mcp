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
- [Calling Tools](#calling-tools)
  - [From a Client](#from-a-client)
  - [From Another Tool](#from-another-tool)
- [Advanced Tool Features](#advanced-tool-features)
  - [Tool Categories](#tool-categories)
  - [Tool Metadata](#tool-metadata)
  - [Tool Permissions](#tool-permissions)
  - [Tool Callbacks](#tool-callbacks)
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

To define a tool, create a class that inherits from `MCP::Tool`:

```ruby
class HelloTool < MCP::Tool
  description "Say hello to someone"
  
  def call(**_args)
    "Hello, world!"
  end
end

# Create a server
server = MCP::Server.new(name: 'example-server', version: '1.0.0')

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
class GreetTool < MCP::Tool
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
class ProcessDataTool < MCP::Tool
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
class DivideTool < MCP::Tool
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
class RepeatTool < MCP::Tool
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

## Calling Tools

### From a Client

To call a tool from a client:

```ruby
client = MCP::Client.new(name: 'example-client', version: '1.0.0')
client.connect('ruby server.rb')

# Call a tool with arguments
result = client.call_tool('greet', { name: 'Alice' })
puts result  # Outputs: Hello, Alice!

# Call a tool with no arguments
result = client.call_tool('hello')
puts result  # Outputs: Hello, world!
```

### From Another Tool

Tools can call other tools through the server instance:

```ruby
class GreetMultipleTool < MCP::Tool
  description "Greet multiple people"
  
  # Class variable to hold server instance
  @server = nil

  # Class methods to get and set server instance
  class << self
    attr_accessor :server
  end
  
  arguments do
    required(:names).array(:string).description("Names of people to greet")
  end
  
  def call(names:)
    raise "Server not set" unless self.class.server
    
    results = names.map do |name|
      # Get the tool instance
      greet_tool = self.class.server.tools["greet"].new
      # Call the tool
      greet_tool.call(name: name)
    end
    
    results.join("\n")
  end
end

# Set the server reference
GreetMultipleTool.server = server

# Register the tool
server.register_tool(GreetMultipleTool)
```

## Advanced Tool Features

### Tool Categories

You can organize tools into categories using instance variables or metadata:

```ruby
class AddTool < MCP::Tool
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

class SubtractTool < MCP::Tool
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

```ruby
class WeatherTool < MCP::Tool
  description "Get the weather for a location"
  
  class << self
    attr_accessor :metadata
  end
  
  self.metadata = {
    author: "John Doe",
    version: "1.0.0",
    tags: ["weather", "forecast"]
  }
  
  arguments do
    required(:location).filled(:string).description("Location to get weather for")
  end
  
  def call(location:)
    # Implementation
    { location: location, temperature: rand(0..30), condition: ["Sunny", "Cloudy", "Rainy"].sample }
  end
end
```

### Tool Permissions

You can implement permission checks:

```ruby
class AdminActionTool < MCP::Tool
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
class IncrementCounterTool < MCP::Tool
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