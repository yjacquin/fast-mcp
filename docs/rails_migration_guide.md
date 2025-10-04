# Rails Migration Guide: Legacy to StreamableHTTP

## Overview

This guide specifically addresses Rails developers using the `FastMcp.mount_in_rails` method. The `mount_in_rails` method has been updated to support the new StreamableHTTP transport while maintaining backward compatibility with existing configurations.

## Current Rails Usage

If you're currently using Fast MCP in Rails, you likely have something like this in your initializer:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.mount_in_rails(
  Rails.application,
  name: 'My Rails App',
  version: '1.0.0',
  path_prefix: '/mcp',
  messages_route: 'messages',
  sse_route: 'sse'
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end
```

## Migration Strategies

### Strategy 1: Automatic Detection (Recommended)

The new `mount_in_rails` method automatically detects which transport to use based on your configuration:

```ruby
# config/initializers/fast_mcp.rb

# Option A: Minimal changes - defaults to StreamableHTTP
FastMcp.mount_in_rails(
  Rails.application,
  name: 'My Rails App',
  version: '1.0.0'
  # No path_prefix, messages_route, or sse_route = StreamableHTTP transport
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end

# Option B: Explicit StreamableHTTP
FastMcp.mount_in_rails(
  Rails.application,
  transport: :streamable_http,  # Explicitly use StreamableHTTP
  name: 'My Rails App',
  version: '1.0.0',
  path: '/mcp'  # Single endpoint instead of path_prefix
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end

# Option C: With authentication
FastMcp.mount_in_rails(
  Rails.application,
  transport: :authenticated,  # Or just use authenticate: true
  name: 'My Rails App',
  version: '1.0.0',
  path: '/mcp',
  auth_token: Rails.application.credentials.mcp_token
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end

# Option D: With OAuth 2.1
FastMcp.mount_in_rails(
  Rails.application,
  transport: :oauth,
  name: 'My Rails App',
  version: '1.0.0',
  path: '/mcp',
  oauth_enabled: true,
  opaque_token_validator: method(:validate_oauth_token),
  require_https: Rails.env.production?
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end
```

### Strategy 2: Gradual Migration

Keep your existing configuration during migration period:

```ruby
# config/initializers/fast_mcp.rb

# Phase 1: Keep existing config (will show deprecation warnings)
FastMcp.mount_in_rails(
  Rails.application,
  name: 'My Rails App',
  version: '1.0.0',
  path_prefix: '/mcp',      # Legacy option - triggers deprecation warning
  messages_route: 'messages',
  sse_route: 'sse'
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end

# Phase 2: Add new endpoint alongside legacy (parallel deployment)
# Add this to test the new transport:
if Rails.env.development?
  FastMcp.mount_in_rails(
    Rails.application,
    transport: :streamable_http,
    name: 'My Rails App (StreamableHTTP)',
    version: '1.0.0',
    path: '/mcp-new'  # Different path for testing
  ) do |server|
    Rails.application.config.after_initialize do
      server.register_tools(*ApplicationTool.descendants)
      server.register_resources(*ApplicationResource.descendants)
    end
  end
end

# Phase 3: Switch to new transport
FastMcp.mount_in_rails(
  Rails.application,
  transport: :streamable_http,
  name: 'My Rails App',
  version: '1.0.0',
  path: '/mcp'
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end
```

## Transport Detection Logic

The `mount_in_rails` method automatically detects which transport to use:

```ruby
# These options trigger OAuth transport:
FastMcp.mount_in_rails(Rails.application, oauth_enabled: true)
FastMcp.mount_in_rails(Rails.application, opaque_token_validator: method(:validate_token))

# These options trigger legacy transport (with deprecation warning):
FastMcp.mount_in_rails(Rails.application, path_prefix: '/mcp')
FastMcp.mount_in_rails(Rails.application, messages_route: 'messages')
FastMcp.mount_in_rails(Rails.application, sse_route: 'sse')

# These options trigger authenticated StreamableHTTP:
FastMcp.mount_in_rails(Rails.application, authenticate: true)
FastMcp.mount_in_rails(Rails.application, auth_token: 'token')

# Default: Basic StreamableHTTP transport
FastMcp.mount_in_rails(Rails.application)
```

## Configuration Changes

### Legacy Configuration

```ruby
# OLD: Legacy configuration
FastMcp.mount_in_rails(
  Rails.application,
  path_prefix: '/mcp',          # Becomes path: '/mcp'
  messages_route: 'messages',   # No longer needed
  sse_route: 'sse',            # No longer needed
  authenticate: true,           # Still works
  auth_token: 'secret',        # Still works
  allowed_origins: ['localhost'],
  localhost_only: true
)
```

### StreamableHTTP Configuration

```ruby
# NEW: StreamableHTTP configuration
FastMcp.mount_in_rails(
  Rails.application,
  transport: :streamable_http,  # Optional - auto-detected
  path: '/mcp',                # Single endpoint
  # No messages_route or sse_route needed
  authenticate: true,           # For authenticated transport
  auth_token: 'secret',        # For authenticated transport
  allowed_origins: ['localhost'],
  localhost_only: true,
  require_https: Rails.env.production?  # New security option
)
```

### OAuth Configuration

```ruby
# NEW: OAuth 2.1 configuration
FastMcp.mount_in_rails(
  Rails.application,
  transport: :oauth,
  path: '/mcp',
  oauth_enabled: true,
  require_https: Rails.env.production?,

  # JWT validation (if using JWT tokens)
  resource_identifier: 'https://api.example.com/mcp',  # For audience binding
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  authorization_servers: ['https://auth.example.com'],

  # Or opaque token validation
  opaque_token_validator: lambda do |token|
    # Your token validation logic
    response = HTTParty.post(
      'https://auth.example.com/oauth/introspect',
      body: { token: token },
      headers: { 'Authorization' => "Basic #{client_credentials}" }
    )

    if response.success? && response['active']
      {
        valid: true,
        scopes: response['scope'].split(' '),
        subject: response['sub']
      }
    else
      { valid: false }
    end
  end,

  # Scope requirements
  tools_scope: 'mcp:tools',
  resources_scope: 'mcp:read',
  admin_scope: 'mcp:admin'
)
```

## Environment-Specific Configuration

### Development Environment

```ruby
# config/initializers/fast_mcp.rb
transport_type = if Rails.env.development?
                   :streamable_http  # No auth needed in development
                 elsif Rails.env.test?
                   :streamable_http  # Simple for testing
                 else
                   :oauth           # OAuth in production
                 end

FastMcp.mount_in_rails(
  Rails.application,
  transport: transport_type,
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path: '/mcp',

  # Development/test specific
  localhost_only: Rails.env.local?,
  require_https: Rails.env.production?,

  # Production OAuth config
  oauth_enabled: Rails.env.production?,
  opaque_token_validator: (method(:validate_oauth_token) if Rails.env.production?),

  # Development auth token
  auth_token: (Rails.application.credentials.mcp_token if Rails.env.development?)
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end
```

### Production Configuration

```ruby
# config/initializers/fast_mcp.rb
FastMcp.mount_in_rails(
  Rails.application,
  transport: :oauth,
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path: '/mcp',

  # Production security
  oauth_enabled: true,
  require_https: true,
  localhost_only: false,
  allowed_origins: Rails.application.config.hosts,

  # OAuth configuration from credentials
  authorization_servers: [Rails.application.credentials.oauth[:issuer]],
  resource_identifier: Rails.application.credentials.oauth[:resource_identifier],
  jwks_uri: Rails.application.credentials.oauth[:jwks_uri],

  # Logging
  logger: Rails.logger
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end

# Helper method for OAuth token validation
def validate_oauth_token(token)
  # Implementation depends on your OAuth provider
  # Example for Auth0, Okta, etc.
  oauth_client = OAuth2::Client.new(
    Rails.application.credentials.oauth[:client_id],
    Rails.application.credentials.oauth[:client_secret],
    site: Rails.application.credentials.oauth[:issuer]
  )

  response = oauth_client.request(:post, '/oauth/introspect', body: { token: token })

  if response.status == 200 && response.parsed['active']
    {
      valid: true,
      scopes: response.parsed['scope'].split(' '),
      subject: response.parsed['sub'],
      client_id: response.parsed['client_id']
    }
  else
    { valid: false }
  end
rescue StandardError => e
  Rails.logger.error("OAuth token validation failed: #{e.message}")
  { valid: false }
end
```

## Generator Updates

The Rails generator will be updated to create modern configurations:

```bash
# Generate new Rails MCP configuration
rails generate fast_mcp:install

# This will create config/initializers/fast_mcp.rb with StreamableHTTP transport
```

New generator template will create:

```ruby
# config/initializers/fast_mcp.rb (generated)
FastMcp.mount_in_rails(
  Rails.application,
  transport: :streamable_http,  # Modern transport by default
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path: '/mcp',

  # Uncomment for authentication:
  # authenticate: true,
  # auth_token: Rails.application.credentials.mcp_token,

  # Uncomment for OAuth 2.1:
  # oauth_enabled: true,
  # opaque_token_validator: method(:validate_oauth_token),

  # Security settings
  require_https: Rails.env.production?,
  localhost_only: Rails.env.local?
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end

# Uncomment if using OAuth 2.1
# def validate_oauth_token(token)
#   # Implement your OAuth token validation here
#   # Return { valid: true/false, scopes: [...], subject: '...' }
# end
```

## Testing Your Migration

### Development Testing

```bash
# Test the new endpoint
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Test SSE endpoint
curl -H "Accept: text/event-stream" \
     -H "MCP-Protocol-Version: 2025-06-18" \
     http://localhost:3000/mcp
```

### Integration Testing

```ruby
# spec/integration/mcp_integration_spec.rb
RSpec.describe 'MCP Integration' do
  describe 'StreamableHTTP Transport' do
    it 'responds to tools/list requests' do
      post '/mcp',
           params: { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json,
           headers: {
             'Content-Type' => 'application/json',
             'Accept' => 'application/json',
             'MCP-Protocol-Version' => '2025-06-18'
           }

      expect(response).to have_http_status(200)
      body = JSON.parse(response.body)
      expect(body['result']['tools']).to be_an(Array)
    end

    it 'supports SSE connections' do
      get '/mcp',
          headers: {
            'Accept' => 'text/event-stream',
            'MCP-Protocol-Version' => '2025-06-18'
          }

      expect(response).to have_http_status(200)
      expect(response.headers['Content-Type']).to eq('text/event-stream')
    end
  end
end
```

## Deployment Considerations

### Rolling Deployment

```ruby
# Deploy with feature flag for gradual rollout
FastMcp.mount_in_rails(
  Rails.application,
  transport: Rails.application.config.mcp_use_streamable_http ? :streamable_http : :legacy,
  name: Rails.application.class.module_parent_name.underscore.dasherize,
  version: '1.0.0',
  path: '/mcp'
) do |server|
  # ... server configuration
end

# Environment variable or feature flag:
# MCP_USE_STREAMABLE_HTTP=true
```

### Load Balancer Configuration

Update your load balancer to handle the unified endpoint:

```nginx
# Nginx configuration
location /mcp {
    proxy_pass http://rails_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # SSE support
    proxy_cache_bypass $http_upgrade;
    proxy_buffering off;
}
```

## Troubleshooting Rails Migration

### Common Issues

1. **Deprecation Warnings**

   ```
   DEPRECATION WARNING: Legacy MCP transport detected in mount_in_rails.
   ```

   **Solution**: Remove `path_prefix`, `messages_route`, and `sse_route` options

2. **404 Not Found**

   ```
   GET /mcp/messages -> 404
   ```

   **Solution**: Update client to use unified `/mcp` endpoint

3. **Authentication Failures**

   ```
   401 Unauthorized
   ```

   **Solution**: Ensure authentication is properly configured and tokens are valid

4. **CORS Issues**
   ```
   CORS policy blocks request
   ```
   **Solution**: Update `allowed_origins` configuration

### Debug Mode

Enable debug logging to troubleshoot issues:

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  transport: :streamable_http,
  logger: Logger.new($stdout, level: Logger::DEBUG),
  # ... other options
)
```

## Best Practices for Rails

1. **Use Environment-Specific Configuration**

   - Development: Basic StreamableHTTP
   - Staging: Authenticated StreamableHTTP
   - Production: OAuth StreamableHTTP

2. **Secure Credentials Management**

   ```bash
   # Store sensitive data in Rails credentials
   rails credentials:edit

   # Add to credentials.yml.enc:
   mcp:
     auth_token: "your-secret-token"
   oauth:
     issuer: "https://auth.example.com"
     client_id: "your-client-id"
     client_secret: "your-client-secret"
   ```

3. **Monitor Performance**

   ```ruby
   # Add metrics collection
   FastMcp.mount_in_rails(
     Rails.application,
     # ... config
   ) do |server|
     server.on_request do |method, duration|
       Rails.logger.info("MCP #{method} completed in #{duration}ms")
       StatsD.timing('mcp.request.duration', duration, tags: ["method:#{method}"])
     end
   end
   ```

4. **Use Rails Conventions**
   ```ruby
   # Follow Rails naming conventions
   FastMcp.mount_in_rails(
     Rails.application,
     name: Rails.application.class.module_parent_name.underscore.dasherize,
     version: Rails.application.config.version || '1.0.0',
     path: '/api/mcp'  # Under your API namespace
   )
   ```

This comprehensive Rails migration guide ensures that Rails developers can smoothly transition from the legacy transport to the modern StreamableHTTP transport while taking advantage of new features like OAuth 2.1 authorization.
