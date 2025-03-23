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
mcp_server.tool "example_tool" do
  description "An example tool"
  argument :input, description: "Input value", type: :string, required: true
  
  call do |args|
    "You provided: #{args[:input]}"
  end
end

# Register resources
mcp_server.register_resource(MCP::Resource.new(
  uri: "example/counter",
  name: "Counter",
  description: "A simple counter resource",
  mime_type: "application/json",
  content: JSON.generate({ count: 0 })
))

# Use the MCP middleware
use MCP::Transports::RackTransport.new(mcp_server)

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
use MCP.rack_middleware(name: 'sinatra-mcp-server', version: '1.0.0') do |server|
  # Define your tools
  server.tool "example_tool" do
    description "An example tool"
    argument :input, description: "Input value", type: :string, required: true
    
    call do |args|
      "You provided: #{args[:input]}"
    end
  end
  
  # Register resources
  server.register_resource(MCP::Resource.new(
    uri: "example/counter",
    name: "Counter",
    description: "A simple counter resource",
    mime_type: "application/json",
    content: JSON.generate({ count: 0 })
  ))
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
  server.tool "process_data" do
    description "Process data using Sinatra helpers"
    argument :input, description: "Input data", type: :string, required: true
    
    call do |args|
      # Access Sinatra helpers and settings
      api_key = settings.api_key
      formatted_data = helpers.format_data(args[:input])
      
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

# Register resources
mcp_server.register_resource(MCP::Resource.new(
  uri: "data/users",
  name: "Users",
  description: "List of all users",
  mime_type: "application/json",
  content: JSON.generate(User.all.map { |user| { id: user.id, name: user.name } })
))

# Use the MCP middleware
use MCP::Transports::RackTransport.new(mcp_server)

# Define a route to create a user
post '/users' do
  # Create the user
  user = User.create(name: params[:name], email: params[:email])
  
  # Update the MCP resource
  mcp_server.update_resource(
    "data/users",
    JSON.generate(User.all.map { |u| { id: u.id, name: u.name } })
  )
  
  # Return the user as JSON
  content_type :json
  { id: user.id, name: user.name, email: user.email }.to_json
end
```

## Creating Routes for MCP

You can create dedicated routes for MCP-related functionality:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Create the MCP server
mcp_server = MCP::Server.new(name: 'sinatra-mcp-server', version: '1.0.0')

# Define your tools and resources
# ...

# Use the MCP middleware
use MCP::Transports::RackTransport.new(mcp_server)

# Define a route to list tools
get '/mcp/tools' do
  @tools = mcp_server.list_tools
  erb :tools
end

# Define a route to list resources
get '/mcp/resources' do
  @resources = mcp_server.list_resources
  erb :resources
end

# Define a route to call a tool
post '/mcp/tools/:name/call' do
  tool_name = params[:name]
  args = JSON.parse(request.body.read).transform_keys(&:to_sym)
  
  begin
    result = mcp_server.call_tool(tool_name, args)
    content_type :json
    { result: result }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# Define a route to read a resource
get '/mcp/resources/:uri' do
  uri = params[:uri]
  
  begin
    resource = mcp_server.read_resource(uri)
    content_type resource[:mime_type]
    resource[:content]
  rescue => e
    status 404
    { error: e.message }.to_json
  end
end
```

## Using the MCP Client in Sinatra

You can use the MCP client to connect to other MCP servers:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Create an MCP client
mcp_client = MCP::Client.new(name: 'sinatra-mcp-client', version: '1.0.0')

# Connect to an external MCP server
mcp_client.connect_http('http://external-mcp-server.example.com')

# Define a route that uses the MCP client
get '/external/tools' do
  @tools = mcp_client.list_tools
  erb :external_tools
end

# Define a route that calls an external tool
post '/external/tools/:name/call' do
  tool_name = params[:name]
  args = JSON.parse(request.body.read).transform_keys(&:to_sym)
  
  begin
    result = mcp_client.call_tool(tool_name, args)
    content_type :json
    { result: result }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# Define a route that reads an external resource
get '/external/resources/:uri' do
  uri = params[:uri]
  
  begin
    resource = mcp_client.read_resource(uri)
    content_type resource[:mime_type]
    resource[:content]
  rescue => e
    status 404
    { error: e.message }.to_json
  end
end
```

## Working with Resources

MCP Resources provide a way to share and synchronize data between your Sinatra application and MCP clients.

### Creating and Registering Resources

```ruby
# Create a resource
resource = MCP::Resource.new(
  uri: "example/counter",
  name: "Counter",
  description: "A simple counter resource",
  mime_type: "application/json",
  content: JSON.generate({ count: 0 })
)

# Register the resource with the server
mcp_server.register_resource(resource)
```

### Updating Resources

You can update resources when your data changes:

```ruby
# Update a resource
counter_data = JSON.parse(resource.content)
counter_data["count"] += 1
mcp_server.update_resource("example/counter", JSON.generate(counter_data))
```

### Accessing Resources in Views

You can access MCP resources in your Sinatra views:

```erb
<!-- views/resources.erb -->
<h1>MCP Resources</h1>

<ul>
  <% @resources.each do |resource| %>
    <li>
      <h2><%= resource[:name] %></h2>
      <p><%= resource[:description] %></p>
      <p>URI: <%= resource[:uri] %></p>
      <p>MIME Type: <%= resource[:mime_type] %></p>
      <% if resource[:mime_type] == "application/json" %>
        <pre><%= JSON.pretty_generate(JSON.parse(resource[:content])) %></pre>
      <% end %>
    </li>
  <% end %>
</ul>
```

### Real-Time Updates with EventSource

You can use Server-Sent Events (SSE) to deliver real-time updates from MCP resources:

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

# Create the MCP server
mcp_server = MCP::Server.new(name: 'sinatra-mcp-server', version: '1.0.0')

# Define your tools and resources
# ...

# Use the MCP middleware
use MCP::Transports::RackTransport.new(mcp_server)

# Define a route for SSE
get '/sse' do
  content_type 'text/event-stream'
  stream(:keep_open) do |out|
    # Send initial data
    out << "data: #{JSON.generate({ type: 'connected' })}\n\n"
    
    # Subscribe to resource updates
    callback = mcp_server.on_resource_update do |resource|
      out << "data: #{JSON.generate({
        type: 'resource_update',
        uri: resource[:uri],
        content: resource[:content]
      })}\n\n"
    end
    
    # Clean up when the connection is closed
    out.callback do
      mcp_server.remove_resource_update_callback(callback)
    end
  end
end
```

Then, in your JavaScript:

```javascript
// Connect to the SSE endpoint
const eventSource = new EventSource('/sse');

// Handle resource updates
eventSource.addEventListener('message', (event) => {
  const data = JSON.parse(event.data);
  
  if (data.type === 'resource_update') {
    // Update the UI with the new resource data
    updateResource(data.uri, data.content);
  }
});
```

## Deployment Considerations

When deploying your Sinatra application with MCP integration, consider the following:

1. **Server Requirements**: Ensure your web server supports SSE for real-time communication.
2. **Load Balancing**: Configure load balancers to handle SSE connections properly.
3. **Timeouts**: Set appropriate timeouts for SSE connections.
4. **Resource Synchronization**: In multi-process environments, ensure resource updates are synchronized across processes.

## Next Steps

- Check out the [examples directory](../examples) for more examples of using MCP.
- Read the [Resources documentation](./resources.md) for more details on using MCP Resources.
- Explore the [advanced configuration options](./advanced_configuration.md) for customizing MCP behavior. 