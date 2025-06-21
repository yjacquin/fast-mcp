# Migration Guide: HTTP+SSE to StreamableHTTP

## Overview

This guide helps you migrate from the legacy HTTP+SSE transport to the new StreamableHTTP transport introduced in MCP 2025-06-18. The StreamableHTTP transport provides improved security, better performance, and OAuth 2.1 integration while maintaining backward compatibility.

## Key Differences

### Legacy HTTP+SSE Transport
- **Two endpoints**: `/mcp/messages` (POST) and `/mcp/sse` (GET)
- Basic token authentication only
- Separate handling for JSON-RPC and SSE
- Limited session management

### StreamableHTTP Transport
- **Single endpoint**: `/mcp` (POST/GET)
- OAuth 2.1 support with scope-based authorization
- Unified request handling
- Advanced session management with secure IDs
- Enhanced security features

## Migration Timeline

### Phase 1: Assessment (Week 1)
- Review current transport usage
- Identify authentication requirements
- Plan OAuth integration (if needed)

### Phase 2: Parallel Implementation (Week 2-3)
- Deploy StreamableHTTP alongside legacy transport
- Test with subset of clients
- Validate functionality and performance

### Phase 3: Migration (Week 4-5)
- Migrate clients to StreamableHTTP
- Monitor for issues
- Update documentation

### Phase 4: Cleanup (Week 6)
- Remove legacy transport usage
- Clean up deprecated code

## Step-by-Step Migration

### 1. Update Dependencies

Ensure you're using the latest version of fast-mcp:

```ruby
# Gemfile
gem 'fast_mcp', '~> 2.0'
```

```bash
bundle update fast_mcp
```

### 2. Legacy Transport Assessment

Identify your current transport usage:

```ruby
# Legacy implementation
transport = FastMcp::Transports::RackTransport.new(
  app, server,
  path_prefix: '/mcp',
  messages_route: 'messages',
  sse_route: 'sse'
)
```

### 3. Choose Migration Path

#### Option A: Basic Migration (Minimal Changes)

```ruby
# Replace with StreamableHTTP
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  path: '/mcp'  # Single endpoint instead of path_prefix
)
```

#### Option B: With Authentication

```ruby
# Add authentication
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  app, server,
  path: '/mcp',
  auth_token: ENV['MCP_AUTH_TOKEN']
)
```

#### Option C: With OAuth 2.1

```ruby
# Full OAuth 2.1 implementation
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  path: '/mcp',
  oauth_enabled: true,
  opaque_token_validator: method(:validate_token),
  require_https: Rails.env.production?
)
```

### 4. Update Client Code

#### Legacy Client Requests

```javascript
// Legacy: Separate endpoints
const messagesUrl = 'http://localhost:3001/mcp/messages';
const sseUrl = 'http://localhost:3001/mcp/sse';

// JSON-RPC request
fetch(messagesUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ jsonrpc: '2.0', method: 'tools/list', id: 1 })
});

// SSE connection
const eventSource = new EventSource(sseUrl);
```

#### StreamableHTTP Client Requests

```javascript
// StreamableHTTP: Single endpoint
const mcpUrl = 'http://localhost:3001/mcp';

// JSON-RPC request (same endpoint)
fetch(mcpUrl, {
  method: 'POST',
  headers: { 
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'MCP-Protocol-Version': '2025-06-18'  // Required header
  },
  body: JSON.stringify({ jsonrpc: '2.0', method: 'tools/list', id: 1 })
});

// SSE connection (same endpoint, different method/headers)
const eventSource = new EventSource(mcpUrl, {
  headers: {
    'Accept': 'text/event-stream',
    'MCP-Protocol-Version': '2025-06-18'
  }
});
```

#### With Authentication

```javascript
// With Bearer token
fetch(mcpUrl, {
  method: 'POST',
  headers: { 
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer your-token-here',
    'MCP-Protocol-Version': '2025-06-18'
  },
  body: JSON.stringify({ jsonrpc: '2.0', method: 'tools/list', id: 1 })
});
```

### 5. Configuration Updates

#### Environment Variables

Update your environment configuration:

```bash
# Legacy
MCP_PATH_PREFIX=/mcp
MCP_MESSAGES_ROUTE=messages
MCP_SSE_ROUTE=sse

# StreamableHTTP
MCP_ENDPOINT_PATH=/mcp
MCP_PROTOCOL_VERSION=2025-06-18
MCP_OAUTH_ENABLED=true
MCP_REQUIRE_HTTPS=true
```

#### Application Configuration

```ruby
# config/initializers/fast_mcp.rb

# Legacy configuration
FastMcp.configure do |config|
  config.transport = :rack
  config.path_prefix = '/mcp'
  config.messages_route = 'messages'
  config.sse_route = 'sse'
end

# StreamableHTTP configuration
FastMcp.configure do |config|
  config.transport = :streamable_http
  config.endpoint_path = '/mcp'
  config.oauth_enabled = Rails.env.production?
  config.require_https = Rails.env.production?
end
```

### 6. Parallel Deployment Strategy

Run both transports simultaneously during migration:

```ruby
# Rack middleware setup for parallel deployment
class Application < Rails::Application
  config.middleware.use FastMcp::Transports::StreamableHttpTransport,
                        server_instance,
                        path: '/mcp'  # New endpoint
  
  # Keep legacy transport temporarily
  config.middleware.use FastMcp::Transports::RackTransport,
                        server_instance,
                        path_prefix: '/legacy-mcp',  # Different path
                        warn_deprecation: true
end
```

### 7. Testing Migration

#### Functional Testing

```ruby
# Test both endpoints work
RSpec.describe 'Transport Migration' do
  it 'legacy transport still works' do
    post '/legacy-mcp/messages', 
         params: { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json,
         headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(200)
  end

  it 'new StreamableHTTP works' do
    post '/mcp',
         params: { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json,
         headers: { 
           'Content-Type' => 'application/json',
           'Accept' => 'application/json',
           'MCP-Protocol-Version' => '2025-06-18'
         }
    expect(response).to have_http_status(200)
  end
end
```

#### Load Testing

```bash
# Test performance comparison
wrk -t4 -c100 -d30s --header "Content-Type: application/json" \
    --header "Accept: application/json" \
    --header "MCP-Protocol-Version: 2025-06-18" \
    -s post-body.lua \
    http://localhost:3001/mcp
```

### 8. Client Migration Scripts

#### Batch Update Client URLs

```ruby
#!/usr/bin/env ruby
# migrate_client_config.rb

require 'json'
require 'find'

def migrate_config_file(file_path)
  content = File.read(file_path)
  
  # Update endpoint URLs
  content.gsub!(/\/mcp\/messages/, '/mcp')
  content.gsub!(/\/mcp\/sse/, '/mcp')
  
  # Add protocol version header
  if content.include?('Content-Type')
    content.gsub!(
      /"Content-Type": "application\/json"/,
      '"Content-Type": "application/json", "MCP-Protocol-Version": "2025-06-18"'
    )
  end
  
  File.write(file_path, content)
  puts "Updated: #{file_path}"
end

# Find and update all config files
Find.find('.') do |path|
  next unless File.file?(path) && path.end_with?('.json', '.js', '.ts')
  next if path.include?('node_modules') || path.include?('.git')
  
  migrate_config_file(path) if File.read(path).include?('/mcp/')
end
```

### 9. Monitoring Migration

#### Metrics to Track

```ruby
# Add monitoring to both transports
class TransportMetrics
  def self.record_request(transport_type, method, status)
    # Your metrics system
    StatsD.increment("mcp.requests", tags: [
      "transport:#{transport_type}",
      "method:#{method}",
      "status:#{status}"
    ])
  end
end

# In your transports
class StreamableHttpTransport
  def handle_mcp_request(request, env)
    result = super
    TransportMetrics.record_request(:streamable_http, request.method, result[0])
    result
  end
end
```

#### Dashboard Queries

```sql
-- Monitor migration progress
SELECT 
  transport_type,
  COUNT(*) as request_count,
  AVG(response_time) as avg_response_time
FROM mcp_requests 
WHERE timestamp > NOW() - INTERVAL 1 DAY
GROUP BY transport_type;

-- Error rates
SELECT 
  transport_type,
  status_code,
  COUNT(*) as error_count
FROM mcp_requests 
WHERE status_code >= 400
  AND timestamp > NOW() - INTERVAL 1 HOUR
GROUP BY transport_type, status_code;
```

### 10. Rollback Plan

If issues arise, you can quickly rollback:

```ruby
# Emergency rollback - disable new transport
FastMcp.configure do |config|
  config.transport = :rack  # Fallback to legacy
  config.streamable_http_enabled = false
end

# Or use feature flag
if FeatureFlag.enabled?(:streamable_http_transport)
  # Use StreamableHTTP
else
  # Use legacy transport
end
```

## Common Migration Issues

### 1. Missing Protocol Version Header

**Problem**: Clients get 400 Bad Request

**Solution**: Add MCP-Protocol-Version header

```javascript
// Add to all requests
headers: {
  'MCP-Protocol-Version': '2025-06-18'
}
```

### 2. Authentication Token Format

**Problem**: 401 Unauthorized with valid token

**Solution**: Check token format

```javascript
// Ensure Bearer prefix for OAuth
headers: {
  'Authorization': 'Bearer ' + token  // Note the space
}

// Or remove Bearer prefix for basic auth
headers: {
  'Authorization': token  // No Bearer prefix
}
```

### 3. CORS Issues

**Problem**: Browser blocks requests

**Solution**: Update CORS configuration

```ruby
# Update allowed origins
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  allowed_origins: [
    'http://localhost:3000',
    'https://myapp.com',
    /\.example\.com$/
  ]
)
```

### 4. SSE Connection Drops

**Problem**: EventSource disconnects frequently

**Solution**: Check session configuration

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  session_timeout: 1800,  # 30 minutes
  keep_alive_interval: 30  # 30 seconds
)
```

### 5. OAuth Scope Issues

**Problem**: 403 Forbidden for valid tokens

**Solution**: Verify scope configuration

```ruby
# Check required scopes
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  tools_scope: 'mcp:tools',     # For tool access
  resources_scope: 'mcp:read',  # For resource access
  admin_scope: 'mcp:admin'      # For admin operations
)
```

## Validation Checklist

Before completing migration:

- [ ] All client endpoints updated to `/mcp`
- [ ] Protocol version headers added to requests
- [ ] Authentication working with new transport
- [ ] SSE connections stable
- [ ] Error handling updated for new response formats
- [ ] Monitoring and logging configured
- [ ] Performance meets requirements
- [ ] Security validation passed
- [ ] Documentation updated
- [ ] Team training completed

## Post-Migration Cleanup

After successful migration:

1. **Remove Legacy Code**
   ```ruby
   # Remove old transport configurations
   # Remove deprecated middleware
   # Clean up environment variables
   ```

2. **Update Documentation**
   - API documentation
   - Client integration guides
   - Deployment procedures

3. **Monitor Performance**
   - Verify improved metrics
   - Confirm security enhancements
   - Validate OAuth functionality

## Support and Resources

- **Issues**: [GitHub Issues](https://github.com/yjacquin/fast-mcp/issues)
- **Documentation**: [Transport Guide](streamable_http_transport.md)
- **OAuth Guide**: [OAuth Integration](oauth_integration.md)
- **Examples**: [Example Applications](../examples/)

## FAQ

**Q: Can I run both transports simultaneously?**
A: Yes, during migration you can run both transports on different paths.

**Q: Is the migration reversible?**
A: Yes, you can rollback to legacy transport if needed.

**Q: What about existing SSE connections?**
A: Existing connections will continue working until client reconnects.

**Q: Do I need to update all clients at once?**
A: No, you can migrate clients gradually using the parallel deployment approach.

**Q: What if I don't need OAuth?**
A: You can use basic StreamableHTTP without OAuth - it's still an improvement over legacy transport.