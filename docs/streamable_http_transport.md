# StreamableHTTP Transport Guide

## Overview

The StreamableHTTP transport implements the MCP 2025-06-18 specification, providing a unified HTTP endpoint that supports both JSON-RPC messaging and Server-Sent Events (SSE) streaming. This transport replaces the legacy HTTP+SSE transport with a more efficient and secure implementation.

## Key Features

- **Unified Endpoint**: Single `/mcp` endpoint for all communication
- **Dual Protocol Support**: POST for JSON-RPC, GET for SSE streaming  
- **Session Management**: Cryptographically secure session IDs
- **OAuth 2.1 Integration**: Comprehensive authorization framework
- **Security**: Origin validation, DNS rebinding protection
- **Backward Compatibility**: Legacy transports still supported

## Quick Start

### Basic StreamableHTTP Transport

```ruby
require 'fast_mcp'

# Create server
server = FastMcp::Server.new(
  name: 'My MCP Server',
  version: '1.0.0'
)

# Add tools and resources
server.add_tool(MyTool.new)
server.add_resource(MyResource.new)

# Create StreamableHTTP transport
transport = FastMcp::Transports::StreamableHttpTransport.new(
  nil, # No Rack app for standalone
  server,
  logger: Logger.new($stdout),
  path: '/mcp'
)

# Start the transport
transport.start
```

### With Authentication

```ruby
# Basic token authentication
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  nil,
  server,
  logger: Logger.new($stdout),
  path: '/mcp',
  auth_token: 'your-secret-token'
)
```

### With OAuth 2.1

```ruby
# OAuth 2.1 with scope-based authorization
opaque_validator = lambda do |token|
  case token
  when 'admin_token'
    { valid: true, scopes: ['mcp:admin', 'mcp:read', 'mcp:write', 'mcp:tools'] }
  when 'read_token'
    { valid: true, scopes: ['mcp:read'] }
  else
    { valid: false }
  end
end

transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  nil,
  server,
  logger: Logger.new($stdout),
  path: '/mcp',
  oauth_enabled: true,
  opaque_token_validator: opaque_validator,
  require_https: false # Allow HTTP for development
)
```

## Endpoint Usage

### JSON-RPC Requests (POST)

```bash
# List available tools
curl -X POST http://localhost:3001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Call a tool
curl -X POST http://localhost:3001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"my_tool","arguments":{"arg1":"value1"}},"id":2}'

# With authentication
curl -X POST http://localhost:3001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer your-token" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### Server-Sent Events (GET)

```bash
# Establish SSE connection
curl -H "Accept: text/event-stream" http://localhost:3001/mcp

# With authentication
curl -H "Accept: text/event-stream" \
     -H "Authorization: Bearer your-token" \
     http://localhost:3001/mcp
```

## Configuration Options

### StreamableHttpTransport Options

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app,                    # Rack app (nil for standalone)
  server,                 # MCP server instance
  logger: Logger.new($stdout),
  path: '/mcp',           # Endpoint path
  localhost_only: true,   # Restrict to localhost
  allowed_origins: ['localhost', '127.0.0.1'],
  allowed_ips: ['127.0.0.1', '::1'],
  session_timeout: 600    # SSE session timeout in seconds
)
```

### Authentication Options

```ruby
# Basic authentication
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  app, server,
  auth_token: 'secret-token',
  auth_header_name: 'Authorization',  # Default
  auth_exempt_paths: ['/health'],     # Skip auth for these paths
  warn_deprecation: false             # Disable deprecation warnings
)
```

### OAuth 2.1 Options

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  require_https: true,                # Enforce HTTPS
  tools_scope: 'mcp:tools',          # Scope for tool access
  resources_scope: 'mcp:read',       # Scope for resource access
  admin_scope: 'mcp:admin',          # Scope for admin operations
  
  # JWT validation options
  issuer: 'https://auth.example.com',
  audience: 'mcp-api',
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  
  # Opaque token validator
  opaque_token_validator: lambda { |token| validate_token(token) }
)
```

## Session Management

### Session ID Generation

Session IDs are automatically generated using cryptographically secure methods:

```ruby
# Generated session IDs are:
# - 32 characters long
# - Alphanumeric only (A-Z, a-z, 0-9)
# - Cryptographically secure
# - Globally unique

# Example: "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6"
```

### Session Lifecycle

1. **Creation**: New session created on first SSE connection
2. **Validation**: Session ID validated on subsequent requests
3. **Resumption**: Existing sessions can be resumed by providing session ID
4. **Timeout**: Sessions expire after configured timeout period
5. **Cleanup**: Expired sessions are automatically cleaned up

### Using Sessions

```bash
# Get session ID from initial SSE connection
curl -H "Accept: text/event-stream" http://localhost:3001/mcp

# Use session ID in subsequent requests
curl -X POST http://localhost:3001/mcp \
  -H "Content-Type: application/json" \
  -H "X-Session-ID: A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

## Security Features

### Origin Validation

Protects against DNS rebinding attacks:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  allowed_origins: [
    'localhost',
    '127.0.0.1',
    /\.example\.com$/,  # Regex patterns supported
    'app.mycompany.com'
  ]
)
```

### Protocol Version Enforcement

Ensures MCP 2025-06-18 compliance:

```ruby
# Requests must include:
# MCP-Protocol-Version: 2025-06-18

# Or will receive 400 Bad Request response
```

### HTTPS Requirements

For OAuth transport in production:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  require_https: true,  # Enforces HTTPS except for localhost
  oauth_enabled: true
)
```

## Error Handling

### HTTP Status Codes

- **200 OK**: Successful JSON-RPC response
- **202 Accepted**: Notification processed (no response)
- **400 Bad Request**: Invalid request format or missing headers
- **401 Unauthorized**: Authentication required or invalid token
- **403 Forbidden**: Insufficient permissions (OAuth scopes)
- **404 Not Found**: Endpoint not found
- **405 Method Not Allowed**: Unsupported HTTP method
- **500 Internal Server Error**: Server error

### Error Response Format

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32600,
    "message": "Invalid Request",
    "data": {
      "error": "invalid_token",
      "error_description": "Token has expired"
    }
  },
  "id": null
}
```

## Integration Examples

### Rack Middleware

```ruby
# config.ru
require 'fast_mcp'

# Your main application
app = lambda do |env|
  [200, {'Content-Type' => 'text/html'}, ['<h1>Main App</h1>']]
end

# Create MCP server
server = FastMcp::Server.new(name: 'My Server', version: '1.0.0')
server.add_tool(MyTool.new)

# Add StreamableHTTP transport as middleware
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  path: '/mcp'
)

run transport
```

### Rails Integration

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Your regular routes
  root 'home#index'
  
  # MCP will be handled by middleware at /mcp
end

# config/application.rb
config.middleware.use FastMcp::Transports::StreamableHttpTransport,
                      FastMcp::Server.instance,
                      path: '/mcp'
```

### Standalone Server

```ruby
#!/usr/bin/env ruby
require 'fast_mcp'
require 'puma'

server = FastMcp::Server.new(name: 'Standalone Server', version: '1.0.0')
server.add_tool(MyTool.new)

transport = FastMcp::Transports::StreamableHttpTransport.new(
  nil, server,
  path: '/mcp'
)

# Use with Puma
app = Rack::Builder.new { run transport }
Puma::Server.new(app).tap do |server|
  server.add_tcp_listener 'localhost', 3001
  server.run
end
```

## Testing

### Using MCP Inspector

```bash
# Test with the official MCP inspector
npx @modelcontextprotocol/inspector http://localhost:3001/mcp
```

### Manual Testing

```bash
# Test JSON-RPC endpoint
curl -X POST http://localhost:3001/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}},"id":1}'

# Test SSE endpoint
curl -H "Accept: text/event-stream" \
     -N http://localhost:3001/mcp
```

### RSpec Testing

```ruby
RSpec.describe 'StreamableHTTP Transport' do
  let(:app) { lambda { |env| [200, {}, ['OK']] } }
  let(:server) { FastMcp::Server.new(name: 'Test', version: '1.0.0') }
  let(:transport) { FastMcp::Transports::StreamableHttpTransport.new(app, server) }

  it 'handles JSON-RPC requests' do
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/mcp',
      'CONTENT_TYPE' => 'application/json',
      'HTTP_ACCEPT' => 'application/json',
      'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
    }
    
    status, headers, body = transport.call(env)
    expect(status).to eq(200)
  end
end
```

## Performance Considerations

### Connection Pooling

- SSE connections are pooled per session
- Multiple clients can share the same session
- Automatic cleanup of stale connections

### Memory Management

- Session data is stored in memory with automatic cleanup
- Connection state is minimal per client
- Thread-safe implementation using mutexes

### Scalability

- Supports multiple concurrent connections
- Efficient message broadcasting to SSE clients
- Minimal overhead for JSON-RPC requests

## Troubleshooting

### Common Issues

1. **CORS Errors**: Check `allowed_origins` configuration
2. **Authentication Failures**: Verify token format and expiration
3. **SSE Connection Drops**: Check network stability and session timeout
4. **Protocol Version Errors**: Ensure client sends MCP-Protocol-Version header

### Debug Logging

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  logger: Logger.new($stdout, level: Logger::DEBUG)
)
```

### Health Checks

```bash
# Basic connectivity test
curl -i http://localhost:3001/mcp

# Should return 400 with missing Accept header error
```

## Migration from Legacy Transport

See the [Migration Guide](migration_guide.md) for detailed instructions on migrating from the legacy HTTP+SSE transport to StreamableHTTP.

## Related Documentation

- [OAuth 2.1 Integration Guide](oauth_integration.md)
- [Transport Comparison](transport_comparison.md)
- [Security Configuration](security_configuration.md)
- [API Reference](api_reference.md)