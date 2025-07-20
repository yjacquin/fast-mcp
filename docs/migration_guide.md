# Migration Guide: HTTP+SSE to StreamableHTTP

## Overview

This guide helps you migrate from the legacy HTTP+SSE transport to the new StreamableHTTP transport introduced in MCP 2025-06-18.

## Key Differences

### Legacy HTTP+SSE Transport
- Two endpoints: `/mcp/messages` (POST) and `/mcp/sse` (GET)
- Basic token authentication only
- Separate handling for JSON-RPC and SSE

### StreamableHTTP Transport
- Single endpoint: `/mcp` (POST/GET)
- OAuth 2.1 support with scope-based authorization
- Unified request handling
- Enhanced security features

## Migration Steps

### 1. Update Dependencies

```ruby
# Gemfile
gem 'fast_mcp', '~> 2.0'
```

### 2. Replace Transport

#### Basic Migration

```ruby
# Before
transport = FastMcp::Transports::RackTransport.new(
  app, server,
  path_prefix: '/mcp',
  messages_route: 'messages',
  sse_route: 'sse'
)

# After
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  path: '/mcp'
)
```

#### With Authentication

```ruby
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  app, server,
  path: '/mcp',
  auth_token: ENV['MCP_AUTH_TOKEN']
)
```

#### With OAuth 2.1 (Resource Server)

```ruby
# Fast MCP acts as OAuth 2.1 Resource Server
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  path: '/mcp',
  oauth_enabled: true,
  authorization_servers: ['https://auth.example.com']  # External authorization server
)
```

### 3. Update Configuration

```ruby
# config/initializers/fast_mcp.rb

# Before
FastMcp.configure do |config|
  config.transport = :rack
  config.path_prefix = '/mcp'
end

# After - Fast MCP as OAuth 2.1 Resource Server
FastMcp.configure do |config|
  config.transport = :streamable_http
  config.endpoint_path = '/mcp'
  config.oauth_enabled = Rails.env.production?

  # External authorization server configuration
  config.oauth_issuer = ENV['OAUTH_ISSUER']
  config.oauth_jwks_uri = ENV['OAUTH_JWKS_URI']
end
```

## Common Issues

### CORS Configuration
Update allowed origins:
```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  allowed_origins: ['http://localhost:3000', 'https://myapp.com']
)
```

## Validation

Test your migration:

```ruby
# Test new endpoint
post '/mcp',
     params: { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json,
     headers: {
       'Content-Type' => 'application/json',
       'Accept' => 'application/json',
       'MCP-Protocol-Version' => '2025-06-18'
     }

expect(response).to have_http_status(200)
```

## Resources

- [StreamableHTTP Transport Guide](streamable_http_transport.md)
- [OAuth Integration Guide](oauth_integration.md)
- [Examples](../examples/)
