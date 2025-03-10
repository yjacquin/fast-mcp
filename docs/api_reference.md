# Fast MCP API Reference

This document provides a comprehensive reference for the Fast MCP API. It covers all the classes, methods, and options available in the library.

## Table of Contents

- [MCP Module](#mcp-module)
- [MCP::Server](#mcpserver)
- [MCP::Resource](#mcpresource)
- [MCP::Tool](#mcptool)
- [MCP::Transports](#mcptransports)
  - [StdioTransport](#stdiotransport)
  - [HttpTransport](#httptransport)
  - [SSETransport](#ssetransport)
  - [RackTransport](#racktransport)

## MCP Module

The `MCP` module is the main namespace for Fast MCP. It provides factory methods for creating servers, clients, and middleware.

### Methods

#### `MCP.rack_middleware(name:, version:, options = {}, &block)`

Creates a Rack middleware for integrating MCP with web frameworks.

**Parameters:**
- `name` (String): The name of the MCP server
- `version` (String): The version of the MCP server
- `options` (Hash): Options for the middleware
  - `path_prefix` (String): The path prefix for MCP endpoints (default: `/mcp`)
  - `sse_path` (String): The path for SSE endpoint (default: `/sse`)
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level
- `block` (Block): A block that receives the server instance for configuration

**Returns:**
- A Rack middleware class

**Example:**
```ruby
use MCP.rack_middleware(name: 'my-server', version: '1.0.0') do |server|
  # Configure the server
end
```

## MCP::Server

The `MCP::Server` class represents an MCP server that hosts tools and resources.

### Constructor

#### `MCP::Server.new(name:, version:, logger: Logger.new(STDOUT))`

Creates a new MCP server.

**Parameters:**
- `name` (String): The name of the server
- `version` (String): The version of the server
- `logger` (Logger): A custom logger (optional)

**Returns:**
- A new `MCP::Server` instance

**Example:**
```ruby
server = MCP::Server.new(name: 'my-server', version: '1.0.0')
```

### Methods

#### `server.tool(name, &block)`

Defines a new tool.

**Parameters:**
- `name` (String): The name of the tool
- `block` (Block): A block that configures the tool

**Returns:**
- The created `MCP::Tool` instance

**Example:**
```ruby
server.tool "greet" do
  description "Greet a person"
  argument :name, description: "Name of the person", type: :string, required: true
  
  call do |args|
    "Hello, #{args[:name]}!"
  end
end
```

#### `server.register_resource(resource)`

Registers a resource with the server.

**Parameters:**
- `resource` (MCP::Resource): The resource to register

**Returns:**
- The registered resource

**Example:**
```ruby
resource = MCP::Resource.new(
  uri: "example/counter",
  name: "Counter",
  description: "A simple counter resource",
  mime_type: "application/json",
  content: JSON.generate({ count: 0 })
)
server.register_resource(resource)
```

#### `server.update_resource(uri, content)`

Updates the content of a resource.

**Parameters:**
- `uri` (String): The URI of the resource to update
- `content` (String): The new content of the resource

**Returns:**
- `true` if the resource was updated, `false` otherwise

**Example:**
```ruby
server.update_resource("example/counter", JSON.generate({ count: 1 }))
```

#### `server.read_resource(uri)`

Reads a resource.

**Parameters:**
- `uri` (String): The URI of the resource to read

**Returns:**
- The resource if found, raises an error otherwise

**Example:**
```ruby
resource = server.read_resource("example/counter")
```

#### `server.remove_resource(uri)`

Removes a resource.

**Parameters:**
- `uri` (String): The URI of the resource to remove

**Returns:**
- The removed resource if found, `nil` otherwise

**Example:**
```ruby
server.remove_resource("example/counter")
```

#### `server.start(options = {})`

Starts the server with the STDIO transport.

**Parameters:**
- `options` (Hash): Options for the transport
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level

**Returns:**
- `true` if the server was started successfully

**Example:**
```ruby
server.start
```

#### `server.start_http(options = {})`

Starts the server with the HTTP transport.

**Parameters:**
- `options` (Hash): Options for the transport
  - `port` (Integer): The port to listen on (default: 4567)
  - `host` (String): The host to bind to (default: '0.0.0.0')
  - `ssl` (Boolean): Whether to use SSL (default: false)
  - `ssl_cert` (String): The SSL certificate file (if ssl is true)
  - `ssl_key` (String): The SSL key file (if ssl is true)
  - `path_prefix` (String): The path prefix for MCP endpoints (default: '/mcp')
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level

**Returns:**
- `true` if the server was started successfully

**Example:**
```ruby
server.start_http(port: 4567)
```

#### `server.start_sse(options = {})`

Starts the server with the SSE transport.

**Parameters:**
- `options` (Hash): Options for the transport
  - `port` (Integer): The port to listen on (default: 4567)
  - `host` (String): The host to bind to (default: '0.0.0.0')
  - `ssl` (Boolean): Whether to use SSL (default: false)
  - `ssl_cert` (String): The SSL certificate file (if ssl is true)
  - `ssl_key` (String): The SSL key file (if ssl is true)
  - `path_prefix` (String): The path prefix for MCP endpoints (default: '/mcp')
  - `sse_path` (String): The path for SSE endpoint (default: '/sse')
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level

**Returns:**
- `true` if the server was started successfully

**Example:**
```ruby
server.start_sse(port: 4567)
```

#### `server.stop`

Stops the server.

**Returns:**
- `true` if the server was stopped successfully

**Example:**
```ruby
server.stop
```

#### `server.on_resource_update(&block)`

Registers a callback for resource updates.

**Parameters:**
- `block` (Block): A block that receives the updated resource

**Returns:**
- A callback ID that can be used to remove the callback

**Example:**
```ruby
callback_id = server.on_resource_update do |resource|
  puts "Resource updated: #{resource[:uri]}"
end
```

#### `server.remove_resource_update_callback(callback_id)`

Removes a resource update callback.

**Parameters:**
- `callback_id` (String): The ID of the callback to remove

**Returns:**
- `true` if the callback was removed, `false` otherwise

**Example:**
```ruby
server.remove_resource_update_callback(callback_id)
```

## MCP::Client

The `MCP::Client` class represents an MCP client that connects to a server to call tools and access resources.

### Constructor

#### `MCP::Client.new(name:, version:, logger: Logger.new(STDOUT), server_url: nil)`

Creates a new MCP client.

**Parameters:**
- `name` (String): The name of the client
- `version` (String): The version of the client
- `logger` (Logger): A custom logger (optional)
- `server_url` (String): The URL of the server to connect to (optional)

**Returns:**
- A new `MCP::Client` instance

**Example:**
```ruby
client = MCP::Client.new(name: 'my-client', version: '1.0.0')
```

### Methods

#### `client.connect(server_command, options = {})`

Connects to a server using the STDIO transport.

**Parameters:**
- `server_command` (String): The command to launch the server
- `options` (Hash): Options for the transport
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level

**Returns:**
- Connection information if successful

**Example:**
```ruby
client.connect('ruby server.rb')
```

#### `client.connect_http(base_url, options = {})`

Connects to a server using the HTTP transport.

**Parameters:**
- `base_url` (String): The base URL of the server
- `options` (Hash): Options for the transport
  - `path_prefix` (String): The path prefix for MCP endpoints (default: '/mcp')
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level

**Returns:**
- Connection information if successful

**Example:**
```ruby
client.connect_http('http://localhost:4567')
```

#### `client.connect_sse(base_url, options = {})`

Connects to a server using the SSE transport.

**Parameters:**
- `base_url` (String): The base URL of the server
- `options` (Hash): Options for the transport
  - `path_prefix` (String): The path prefix for MCP endpoints (default: '/mcp')
  - `sse_path` (String): The path for SSE endpoint (default: '/sse')
  - `logger` (Logger): A custom logger
  - `log_level` (Integer): The log level

**Returns:**
- Connection information if successful

**Example:**
```ruby
client.connect_sse('http://localhost:4567')
```

#### `client.disconnect`

Disconnects from the server.

**Returns:**
- `true` if disconnected successfully

**Example:**
```ruby
client.disconnect
```

#### `client.list_tools`

Lists the tools available on the server.

**Returns:**
- An array of tool information

**Example:**
```ruby
tools = client.list_tools
```

#### `client.call_tool(name, arguments = {})`

Calls a tool on the server.

**Parameters:**
- `name` (String): The name of the tool to call
- `arguments` (Hash): The arguments to pass to the tool

**Returns:**
- The result of the tool call

**Example:**
```ruby
result = client.call_tool('greet', { name: 'Alice' })
```

#### `client.list_resources`

Lists the resources available on the server.

**Returns:**
- An array of resource information

**Example:**
```ruby
resources = client.list_resources
```

#### `client.read_resource(uri)`

Reads a resource from the server.

**Parameters:**
- `uri` (String): The URI of the resource to read

**Returns:**
- The resource if found

**Example:**
```ruby
resource = client.read_resource('example/counter')
```

#### `client.subscribe_to_resource(uri, &callback)`

Subscribes to updates for a resource.

**Parameters:**
- `uri` (String): The URI of the resource to subscribe to
- `callback` (Block): A block that receives the updated resource

**Returns:**
- `true` if subscribed successfully

**Example:**
```ruby
client.subscribe_to_resource('example/counter') do |resource|
  puts "Counter updated: #{JSON.parse(resource.content)['count']}"
end
```

#### `client.unsubscribe_from_resource(uri)`

Unsubscribes from updates for a resource.

**Parameters:**
- `uri` (String): The URI of the resource to unsubscribe from

**Returns:**
- `true` if unsubscribed successfully

**Example:**
```ruby
client.unsubscribe_from_resource('example/counter')
```

## MCP::Resource

The `MCP::Resource` class represents a resource in the MCP system. Resources can be created either by inheriting from the class or by using the constructor directly.

### Class Definition

To create a resource by inheriting from `MCP::Resource`:

```ruby
class MyResource < MCP::Resource
  uri "example/my-resource"
  name "My Resource"
  description "An example resource"
  mime_type "application/json"
  
  def content
    JSON.generate({ value: "Hello, World!" })
  end
  
  def update_content(new_content)
    # Handle content updates
  end
end

# Create an instance
resource = MyResource.new

# Register with the server
server.register_resource(resource)
```

### Class Methods

#### `MCP::Resource.uri(value = nil)`

Sets or gets the URI for this resource class.

**Parameters:**
- `value` (String): The URI of the resource (optional)

**Returns:**
- The URI if no value is provided, otherwise sets the URI

**Example:**
```ruby
class MyResource < MCP::Resource
  uri "example/my-resource"
end
```

#### `MCP::Resource.name(value = nil)`

Sets or gets the name for this resource class.

**Parameters:**
- `value` (String): The name of the resource (optional)

**Returns:**
- The name if no value is provided, otherwise sets the name

**Example:**
```ruby
class MyResource < MCP::Resource
  name "My Resource"
end
```

#### `MCP::Resource.description(value = nil)`

Sets or gets the description for this resource class.

**Parameters:**
- `value` (String): The description of the resource (optional)

**Returns:**
- The description if no value is provided, otherwise sets the description

**Example:**
```ruby
class MyResource < MCP::Resource
  description "An example resource"
end
```

#### `MCP::Resource.mime_type(value = nil)`

Sets or gets the MIME type for this resource class.

**Parameters:**
- `value` (String): The MIME type of the resource (optional)

**Returns:**
- The MIME type if no value is provided, otherwise sets the MIME type

**Example:**
```ruby
class MyResource < MCP::Resource
  mime_type "application/json"
end
```

#### `MCP::Resource.from_file(file_path, name: nil, description: nil)`

Creates a resource from a file.

**Parameters:**
- `file_path` (String): The path to the file
- `name` (String): The name of the resource (optional, defaults to file name)
- `description` (String): The description of the resource (optional)

**Returns:**
- A new `MCP::Resource` instance

**Example:**
```ruby
resource = MCP::Resource.from_file("path/to/image.png")
```

### Constructor

#### `MCP::Resource.new(uri: nil, name: nil, description: nil, mime_type: nil, content: nil, binary: false)`

Creates a new resource instance directly.

**Parameters:**
- `uri` (String): The URI of the resource
- `name` (String): The name of the resource
- `description` (String): The description of the resource
- `mime_type` (String): The MIME type of the resource
- `content` (String): The content of the resource - Note: The base Resource class requires override of the content method. This parameter is for documentation completeness but isn't actually used in the constructor.
- `binary` (Boolean): Whether the content is binary (optional)

**Returns:**
- A new `MCP::Resource` instance

**Example:**
```ruby
# To create a usable resource directly, you'd typically
# provide a custom implementation of the content method:
class SimpleCounterResource < MCP::Resource
  uri "example/counter"
  name "Counter"
  description "A simple counter resource"
  mime_type "application/json"
  
  def content
    JSON.generate({ count: 0 })
  end
  
  def update_content(new_content)
    # Handle content updates
  end
end

# Then create an instance
resource = SimpleCounterResource.new
```

### Instance Methods

#### `resource.uri`

Gets the URI of the resource.

**Returns:**
- The URI of the resource

**Example:**
```ruby
uri = resource.uri
```

#### `resource.name`

Gets the name of the resource.

**Returns:**
- The name of the resource

**Example:**
```ruby
name = resource.name
```

#### `resource.description`

Gets the description of the resource.

**Returns:**
- The description of the resource

**Example:**
```ruby
description = resource.description
```

#### `resource.mime_type`

Gets the MIME type of the resource.

**Returns:**
- The MIME type of the resource

**Example:**
```ruby
mime_type = resource.mime_type
```

#### `resource.content`

Gets the content of the resource. This method should be implemented in custom resource classes.

**Returns:**
- The content of the resource

**Example:**
```ruby
content = resource.content
```

#### `resource.update_content(new_content)`

Updates the content of the resource. This method should be implemented in custom resource classes to handle content updates.

**Parameters:**
- `new_content` (String): The new content for the resource

**Example:**
```ruby
resource.update_content(JSON.generate({ count: 1 }))
```

#### `resource.binary?`

Checks if the resource content is binary.

**Returns:**
- `true` if the content is binary, `false` otherwise

**Example:**
```ruby
is_binary = resource.binary?
```

#### `resource.to_h`

Converts the resource to a hash.

**Returns:**
- A hash representation of the resource

**Example:**
```ruby
hash = resource.to_h
```

## MCP::Tool

The `MCP::Tool` class represents a tool in the MCP system. Tools are created by inheriting from this class and implementing the required methods.

### Class Definition

To create a tool by inheriting from `MCP::Tool`:

```ruby
class GreetTool < MCP::Tool
  description "Greet a person"
  
  arguments do
    required(:name).filled(:string).description("Name of the person")
    optional(:title).filled(:string).description("Title of the person")
  end
  
  def call(name:, title: nil)
    if title
      "Hello, #{title} #{name}!"
    else
      "Hello, #{name}!"
    end
  end
end

# Register with the server
server.register_tool(GreetTool)
```

### Class Methods

#### `MCP::Tool.description(value = nil)`

Sets or gets the description for this tool class.

**Parameters:**
- `value` (String): The description of the tool (optional)

**Returns:**
- The description if no value is provided, otherwise sets the description

**Example:**
```ruby
class MyTool < MCP::Tool
  description "My example tool"
end
```

#### `MCP::Tool.arguments(&block)`

Defines the schema for the tool's arguments using Dry::Schema.

**Parameters:**
- `block` (Block): A block with Dry::Schema definitions

**Example:**
```ruby
class MyTool < MCP::Tool
  arguments do
    required(:name).filled(:string).description("Name parameter")
    optional(:count).filled(:integer).description("Count parameter")
  end
end
```

#### `MCP::Tool.name(value = nil)`

Sets or gets the name for this tool class. If not provided, it will use the class name converted to a tool name format.

**Parameters:**
- `value` (String): The name of the tool (optional)

**Returns:**
- The name if no value is provided, otherwise sets the name

**Example:**
```ruby
class MyTool < MCP::Tool
  name "my-custom-tool-name"
end
```

#### `MCP::Tool.input_schema`

Gets the Dry::Schema for validating arguments.

**Returns:**
- The Dry::Schema for this tool

**Example:**
```ruby
schema = MyTool.input_schema
```

#### `MCP::Tool.input_schema_to_json`

Converts the input schema to a JSON schema format for client consumption.

**Returns:**
- A JSON schema representation of the input schema

**Example:**
```ruby
json_schema = MyTool.input_schema_to_json
```

### Instance Methods

#### `tool.call(**args)`

The main method to implement in your tool subclass. This is where the tool's functionality goes.

**Parameters:**
- `args` (Hash): The arguments passed to the tool as keyword arguments

**Returns:**
- The result of the tool execution

**Example:**
```ruby
def call(name:, count: 1)
  "Hello, #{name}!" * count
end
```

#### `tool.call_with_schema_validation!(**args)`

Calls the tool with schema validation. This method is used internally by the server.

**Parameters:**
- `args` (Hash): The arguments to validate and pass to the tool

**Returns:**
- The result of the tool execution

**Raises:**
- `MCP::Tool::InvalidArgumentsError`: If the arguments do not match the schema

**Example:**
```ruby
begin
  result = tool.call_with_schema_validation!(name: "Alice")
rescue MCP::Tool::InvalidArgumentsError => e
  puts "Invalid arguments: #{e.message}"
end
```

## MCP::Transports

The `MCP::Transports` module contains transport implementations for MCP.

### StdioTransport

The `MCP::Transports::StdioTransport` class implements the STDIO transport.

### HttpTransport

The `MCP::Transports::HttpTransport` class implements the HTTP transport.

### SSETransport

The `MCP::Transports::SSETransport` class implements the SSE transport.

### RackTransport

The `MCP::Transports::RackTransport` class implements the Rack transport.
