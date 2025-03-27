# Integrating MCP with Sinatra Applications

This guide explains how to integrate the Model Context Protocol (MCP) with your Sinatra application using the Fast MCP library.

## Installation

Add the Fast MCP gem to your application's Gemfile:

```ruby
gem 'fast-mcp'
```

Then run:

```bash
bundle install
```

## Basic Integration

Sinatra applications can integrate with MCP using the Rack middleware approach. This allows you to embed the MCP server directly in your Sinatra application.

### Using Rack Middleware

Add the MCP middleware to your Sinatra application:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Create the MCP server
mcp_server = MCP::Server.new(name: 'sinatra-mcp-server', version: '1.0.0')

# Define your tools
class ExampleTool < Mcp::Tool
  description "An example tool"
  arguments  do
   required(:input).filled(:string).description("Input value")
  end
  
  def call(input:)
    "You provided: #{input}"
  end
end

# Register resources
class Counter < MCP::Resource
  uri "example/counter"
  resource_name "Counter",
  description "A simple counter resource"
  mime_type "application/json"

  def initialize
    @count = 0
  end

  attr_accessor :count

  def content
    JSON.generate({ count: @count })
  end
end


# Use the MCP middleware
use MCP::Transports::RackTransport, server

# Define your Sinatra routes
get '/' do
  'Hello, world!'
end
```


### Using Authenticated Rack Middleware

Add the MCP authenticated rack middleware to your Sinatra application:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Create the MCP server
mcp_server = MCP::Server.new(name: 'sinatra-mcp-server', version: '1.0.0')

# Define your tools
class ExampleTool < Mcp::Tool
  description "An example tool"
  arguments  do
   required(:input).filled(:string).description("Input value")
  end
  
  def call(input:)
    "You provided: #{input}"
  end
end

# Register resources
class Counter < MCP::Resource
  uri "example/counter"
  resource_name "Counter",
  description "A simple counter resource"
  mime_type "application/json"

  def initialize
    @count = 0
  end

  attr_accessor :count

  def content
    JSON.generate({ count: @count })
  end
end


# Use the MCP middleware
use MCP::Transports::AuthenticatedRackTransport, server

# Define your Sinatra routes
get '/' do
  'Hello, world!'
end
```

### Alternative: Using a Configuration Block

For more complex applications, you might prefer to use a configuration block:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Use the MCP middleware with a configuration block
use FastMcp.rack_middleware, { name: 'sinatra-mcp-server', version: '1.0.0'} do |server|
  # Define your tools, here with anonymous classes
  tool = Class.new(Mcp::Tool) do
    description "An example tool"
    tool_name "Example"

    arguments  do
      required(:input).filled(:string).description("Input value")
    end
    
    def call(input:)
      "You provided: #{input}"
    end
  end
  server.register_tool(tool)
  
  # Register resources
  counter_resource = Class.new(MCP::Resource) do
    uri "example/counter"
    resource_name "Counter",
    description "A simple counter resource"
    mime_type "application/json"

    def initialize
      @count = 0
    end

    attr_accessor :count

    def content
      JSON.generate({ count: @count })
    end
  end

  server.register_resource(counter_resource)
end

# Define your Sinatra routes
get '/' do
  'Hello, world!'
end
```

## Advanced Integration

### Accessing Sinatra Helpers and Settings

You can access Sinatra helpers and settings from your MCP tools and resources:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Define a helper method
helpers do
  def format_data(data)
    # Format the data
    data.upcase
  end
end

# Set a setting
set :api_key, ENV['API_KEY']

# Use the MCP middleware
use MCP.rack_middleware(name: 'sinatra-mcp-server', version: '1.0.0') do |server|
  # Define a tool that uses Sinatra helpers and settings
  class ProcessDataTool < Mcp::Tool
    description "Process data using Sinatra helpers"
    arguments do
      required(:input).filled(:string).description("Input data")
    end
    
    def call(input:)
      # Access Sinatra helpers and settings
      api_key = settings.api_key
      formatted_data = helpers.format_data(input)
      
      # Return the result
      { status: "success", result: formatted_data }
    end
  end
end
```

### Accessing Database Models

If you're using a database with Sinatra (e.g., ActiveRecord, Sequel), you can access your models from MCP tools and resources:

```ruby
# app.rb
require 'sinatra'
require 'sinatra/activerecord'
require 'fast_mcp'

# Define your models
class User < ActiveRecord::Base
  # ...
end

# Use the MCP middleware
use MCP.rack_middleware(name: 'sinatra-mcp-server', version: '1.0.0') do |server|
  # Define a tool that uses ActiveRecord models
  server.tool "search_users" do
    description "Search for users by name"
    argument :query, description: "Search query", type: :string, required: true
    
    call do |args|
      # Use ActiveRecord to search for users
      users = User.where("name LIKE ?", "%#{args[:query]}%")
      
      # Return the results
      users.map { |user| { id: user.id, name: user.name, email: user.email } }
    end
  end
  
  # Register a resource that uses ActiveRecord models
  server.register_resource(MCP::Resource.new(
    uri: "data/users",
    name: "Users",
    description: "List of all users",
    mime_type: "application/json",
    content: JSON.generate(User.all.map { |user| { id: user.id, name: user.name } })
  ))
end
```

### Dynamic Resource Updates

You can update resources based on changes in your Sinatra application:

```ruby
# app.rb
require 'sinatra'
require 'sinatra/activerecord'
require 'fast_mcp'

# Define your models
class User < ActiveRecord::Base
  # ...
end

# Create the MCP server
mcp_server = MCP::Server.new(name: 'sinatra-mcp-server', version: '1.0.0')

class Users < Mcp::Resource
  uri "data/users"
  resource_name "Users"
  description "List of all users"
  mime_type "application/json"
  
  
  def content
    JSON.generate(User.all.map { |user| { id: user.id, name: user.name } })
  end
end

class CreateUserTool < Mcp::Tool
  description "Create a User"
  arguments do
    required(:name).filled(:string).description("The user's name")
  end

  def call(name:)
    User.create!(name:)
  end
end

# Register resources
mcp_server.register_resource(Users)
mcp_server.register_tool(CreateUserTool)

# Use the MCP middleware
use MCP::Transports::RackTransport, mcp_server


## Deployment Considerations

When deploying your Sinatra application with MCP integration, consider the following:

1. **Server Requirements**: Ensure your web server supports SSE for real-time communication.
2. **Load Balancing**: Configure load balancers to handle SSE connections properly.
3. **Timeouts**: Set appropriate timeouts for SSE connections.
4. **Resource Synchronization**: In multi-process environments, ensure resource updates are synchronized across processes.

## Next Steps

- Check out the [examples directory](../examples) for more examples of using MCP.
- Read the [Resources documentation](./resources.md) for more details on using MCP Resources.
