# MCP Transports

Transports are the communication channels between MCP servers and clients. Fast MCP supports multiple transport options to suit different use cases. This guide covers the available transports, how to use them, and when to choose each one.

## Table of Contents

- [MCP Transports](#mcp-transports)
  - [Table of Contents](#table-of-contents)
  - [What are MCP Transports?](#what-are-mcp-transports)
  - [Available Transports](#available-transports)
    - [STDIO Transport](#stdio-transport)
    - [HTTP Transport](#http-transport)
    - [SSE Transport](#sse-transport)
    - [Rack Transport](#rack-transport)
  - [Choosing a Transport](#choosing-a-transport)
  - [Transport Configuration](#transport-configuration)
    - [STDIO Transport](#stdio-transport-1)
    - [HTTP Transport](#http-transport-1)
    - [SSE Transport](#sse-transport-1)
    - [Rack Transport](#rack-transport-1)
  - [Custom Transports](#custom-transports)
  - [Best Practices](#best-practices)

## What are MCP Transports?

In the Model Context Protocol, transports handle the communication between servers and clients. They are responsible for:

- Sending requests from clients to servers
- Sending responses from servers to clients
- Notifying clients of resource updates
- Managing connections and disconnections

Fast MCP abstracts the transport layer, allowing you to use different transports without changing your tool and resource code.

## Available Transports

### STDIO Transport

The STDIO transport uses standard input/output for communication. It's the simplest transport and is ideal for local communication between processes.

**Server Side:**

```ruby
server = MCP::Server.new(name: 'stdio-server', version: '1.0.0')
# Define tools and resources
server.start  # Uses STDIO transport by default
```

**Client Side:**

```ruby
client = MCP::Client.new(name: 'stdio-client', version: '1.0.0')
client.connect('ruby server.rb')  # Launches the server as a subprocess
```

**Pros:**
- Simple to use
- No network configuration required
- Suitable for local development

**Cons:**
- Limited to local communication
- No support for multiple clients
- Not suitable for web applications

### HTTP Transport

The HTTP transport uses HTTP requests for communication. It's suitable for web applications and remote communication.

**Server Side:**

```ruby
server = MCP::Server.new(name: 'http-server', version: '1.0.0')
# Define tools and resources
server.start_http(port: 4567)
```

**Client Side:**

```ruby
client = MCP::Client.new(name: 'http-client', version: '1.0.0')
client.connect_http('http://localhost:4567')
```

**Pros:**
- Works over the network
- Supports multiple clients
- Compatible with web applications
- Works through firewalls (uses standard HTTP ports)

**Cons:**
- More complex setup
- No built-in real-time updates (polling required)
- Higher latency than STDIO

### SSE Transport

The Server-Sent Events (SSE) transport uses HTTP for requests and SSE for real-time updates. It's ideal for applications that need real-time updates.

**Server Side:**

```ruby
server = MCP::Server.new(name: 'sse-server', version: '1.0.0')
# Define tools and resources
server.start_sse(port: 4567)
```

**Client Side:**

```ruby
client = MCP::Client.new(name: 'sse-client', version: '1.0.0')
client.connect_sse('http://localhost:4567')
```

**Pros:**
- Real-time updates
- Works over the network
- Supports multiple clients
- Compatible with web applications

**Cons:**
- More complex setup
- Requires SSE support in the client
- May not work with all proxies and firewalls

### Rack Transport

The Rack transport integrates with Rack-compatible web frameworks like Rails, Sinatra, and Hanami. It's ideal for adding MCP to existing web applications.

**Server Side:**

```ruby
# In a Rails application (config/application.rb)
config.middleware.use MCP.rack_middleware(name: 'rack-server', version: '1.0.0') do |server|
  # Define tools and resources
end

# In a Sinatra application
use MCP.rack_middleware(name: 'rack-server', version: '1.0.0') do |server|
  # Define tools and resources
end
```

**Client Side:**

```ruby
client = MCP::Client.new(name: 'rack-client', version: '1.0.0')
client.connect_http('http://localhost:3000/mcp')  # Adjust the path as needed
```

**Pros:**
- Integrates with existing web applications
- Reuses the web server's configuration
- Supports authentication and other middleware

**Cons:**
- Tied to the web application's lifecycle
- May require additional configuration for real-time updates

## Choosing a Transport

Here's a guide to help you choose the right transport:

- **Local Development**: Use the STDIO transport for simplicity
- **Web Applications**: Use the Rack transport for integration with web frameworks
- **Standalone Servers**: Use the HTTP transport for basic network communication
- **Real-time Applications**: Use the SSE transport for real-time updates

## Transport Configuration

Each transport supports various configuration options:

### STDIO Transport

```ruby
# Server side
server.start(
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)

# Client side
client.connect(
  'ruby server.rb',
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)
```

### HTTP Transport

```ruby
# Server side
server.start_http(
  port: 4567,                  # Port to listen on
  host: '0.0.0.0',             # Host to bind to
  ssl: false,                  # Whether to use SSL
  ssl_cert: 'cert.pem',        # SSL certificate (if ssl is true)
  ssl_key: 'key.pem',          # SSL key (if ssl is true)
  path_prefix: '/mcp',         # Path prefix for MCP endpoints
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)

# Client side
client.connect_http(
  'http://localhost:4567',
  path_prefix: '/mcp',         # Path prefix for MCP endpoints
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)
```

### SSE Transport

```ruby
# Server side
server.start_sse(
  port: 4567,                  # Port to listen on
  host: '0.0.0.0',             # Host to bind to
  ssl: false,                  # Whether to use SSL
  ssl_cert: 'cert.pem',        # SSL certificate (if ssl is true)
  ssl_key: 'key.pem',          # SSL key (if ssl is true)
  path_prefix: '/mcp',         # Path prefix for MCP endpoints
  sse_path: '/sse',            # Path for SSE endpoint
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)

# Client side
client.connect_sse(
  'http://localhost:4567',
  path_prefix: '/mcp',         # Path prefix for MCP endpoints
  sse_path: '/sse',            # Path for SSE endpoint
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)
```

### Rack Transport

```ruby
# In a web application
use MCP.rack_middleware(
  name: 'rack-server',         # Server name
  version: '1.0.0',            # Server version
  path_prefix: '/mcp',         # Path prefix for MCP endpoints
  sse_path: '/sse',            # Path for SSE endpoint
  logger: Logger.new(STDOUT),  # Custom logger
  log_level: Logger::INFO      # Log level
)
```

## Custom Transports

You can create custom transports by implementing the transport interface:

```ruby
module MCP
  module Transports
    class CustomTransport
      def initialize(server, options = {})
        @server = server
        @options = options
        @logger = options[:logger] || Logger.new(STDOUT)
      end
      
      def start
        # Implementation
      end
      
      def stop
        # Implementation
      end
      
      def send_notification(notification)
        # Implementation
      end
      
      # Other required methods
    end
  end
end

# Use the custom transport
server = MCP::Server.new(name: 'custom-server', version: '1.0.0')
# Define tools and resources
server.start_with_transport(MCP::Transports::CustomTransport, custom_option: 'value')
```

## Best Practices

When working with transports, follow these best practices:

1. **Choose the Right Transport**: Select the transport that best fits your use case
2. **Configure Logging**: Set up appropriate logging to debug transport issues
3. **Handle Disconnections**: Implement reconnection logic in clients
4. **Secure Your Transport**: Use SSL for production deployments
5. **Test Different Scenarios**: Test with different network conditions and client types
6. **Monitor Performance**: Keep an eye on transport performance, especially for real-time applications
7. **Consider Scale**: Plan for scaling if you expect many clients

For more details on specific transports, see the examples in the [examples directory](../examples). 