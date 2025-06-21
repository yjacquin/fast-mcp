# Transport Comparison Guide

## Overview

Fast MCP supports multiple transport implementations to suit different use cases and environments. This guide compares the available transports and helps you choose the right one for your application.

## Available Transports

### 1. STDIO Transport
- **Use Case**: Command-line tools and scripts
- **Status**: ✅ Stable
- **Protocol**: Direct stdin/stdout communication

### 2. RackTransport (Legacy)
- **Use Case**: HTTP+SSE with separate endpoints
- **Status**: ⚠️ Deprecated (maintained for compatibility)
- **Protocol**: HTTP with separate `/messages` and `/sse` endpoints

### 3. StreamableHttpTransport
- **Use Case**: Modern HTTP with unified endpoint
- **Status**: ✅ Recommended
- **Protocol**: MCP 2025-06-18 StreamableHTTP

### 4. AuthenticatedStreamableHttpTransport
- **Use Case**: HTTP with token authentication
- **Status**: ✅ Production Ready
- **Protocol**: StreamableHTTP + Bearer token auth

### 5. OAuthStreamableHttpTransport
- **Use Case**: HTTP with OAuth 2.1 authorization
- **Status**: ✅ Production Ready
- **Protocol**: StreamableHTTP + OAuth 2.1

## Detailed Comparison

### Feature Matrix

| Feature | STDIO | RackTransport | StreamableHTTP | Authenticated | OAuth |
|---------|-------|---------------|----------------|---------------|-------|
| **Protocol Compliance** | N/A | Legacy | 2025-06-18 | 2025-06-18 | 2025-06-18 |
| **HTTP Support** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **SSE Streaming** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Authentication** | ❌ | Basic | None | Token | OAuth 2.1 |
| **Authorization** | ❌ | ❌ | ❌ | ❌ | Scope-based |
| **Session Management** | ❌ | Basic | Advanced | Advanced | Advanced |
| **Security Headers** | ❌ | Basic | Enhanced | Enhanced | Enhanced |
| **Origin Validation** | ❌ | Basic | Advanced | Advanced | Advanced |
| **Multi-client Support** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Production Ready** | ✅ | ⚠️ | ✅ | ✅ | ✅ |

### Performance Comparison

| Metric | STDIO | RackTransport | StreamableHTTP | Authenticated | OAuth |
|--------|-------|---------------|----------------|---------------|-------|
| **Latency** | Lowest | Medium | Low | Low | Medium |
| **Throughput** | High | Medium | High | High | Medium |
| **Memory Usage** | Lowest | Medium | Low | Low | Medium |
| **CPU Overhead** | Lowest | Medium | Low | Low | Medium |
| **Scalability** | Single | Multi | Multi | Multi | Multi |

### Security Comparison

| Security Feature | STDIO | RackTransport | StreamableHTTP | Authenticated | OAuth |
|------------------|-------|---------------|----------------|---------------|-------|
| **Network Encryption** | N/A | Optional | HTTPS | HTTPS | HTTPS |
| **Authentication** | OS-level | None/Basic | None | Token | OAuth 2.1 |
| **Authorization** | OS-level | None | None | None | Scope-based |
| **Session Security** | N/A | Basic | Strong | Strong | Strong |
| **Token Validation** | N/A | None | None | Basic | JWT/Opaque |
| **Rate Limiting** | N/A | Manual | Built-in | Built-in | Built-in |
| **Audit Logging** | Manual | Basic | Enhanced | Enhanced | Enhanced |

## Transport Selection Guide

### Choose STDIO Transport When:

```ruby
transport = FastMcp::Transports::StdioTransport.new(server)
```

**Ideal for:**
- Command-line tools
- Shell scripts
- CI/CD pipelines
- Local development utilities
- Single-user applications

**Pros:**
- Simplest setup
- Lowest overhead
- Direct process communication
- No network configuration needed

**Cons:**
- No multi-client support
- No web browser compatibility
- Limited to local execution

**Example Use Cases:**
- Git hooks
- Build tools
- Data processing scripts
- Development tooling

### Choose StreamableHTTP Transport When:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  path: '/mcp'
)
```

**Ideal for:**
- Public APIs
- Web applications
- Development servers
- Multi-client scenarios
- Browser-based tools

**Pros:**
- MCP 2025-06-18 compliant
- Modern unified endpoint
- Excellent performance
- Advanced session management
- Strong security features

**Cons:**
- No built-in authentication
- Requires manual security setup

**Example Use Cases:**
- API servers
- Development tools
- Browser extensions
- Client SDKs

### Choose Authenticated StreamableHTTP When:

```ruby
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  app, server,
  path: '/mcp',
  auth_token: ENV['MCP_TOKEN']
)
```

**Ideal for:**
- Internal APIs
- Microservices
- Trusted environments
- Simple authentication needs

**Pros:**
- Simple token authentication
- All StreamableHTTP benefits
- Quick to implement
- Good for internal use

**Cons:**
- Limited authorization features
- Token management complexity
- Less suitable for multi-tenant

**Example Use Cases:**
- Internal microservices
- Team development tools
- CI/CD integrations
- Service-to-service communication

### Choose OAuth StreamableHTTP When:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  path: '/mcp',
  oauth_enabled: true,
  opaque_token_validator: method(:validate_token)
)
```

**Ideal for:**
- Public APIs
- Multi-tenant applications
- Enterprise integrations
- Third-party access
- Fine-grained permissions

**Pros:**
- Industry-standard OAuth 2.1
- Scope-based authorization
- JWT and opaque token support
- Enterprise-grade security
- Scalable permission model

**Cons:**
- Complex setup
- OAuth server requirement
- Higher latency
- More moving parts

**Example Use Cases:**
- SaaS platforms
- API marketplaces
- Enterprise integrations
- Third-party applications
- Multi-tenant systems

### Avoid RackTransport (Legacy) Unless:

```ruby
# Only use for backward compatibility
transport = FastMcp::Transports::RackTransport.new(
  app, server,
  path_prefix: '/mcp',
  warn_deprecation: false  # Suppress warnings
)
```

**Only use when:**
- Migrating existing systems
- Legacy client compatibility required
- Temporary transition period

**Migration path:** See [Migration Guide](migration_guide.md)

## Migration Recommendations

### From STDIO to HTTP

```ruby
# Before: STDIO only
server = FastMcp::Server.new(name: 'My Tool', version: '1.0.0')
transport = FastMcp::Transports::StdioTransport.new(server)

# After: Support both STDIO and HTTP
if ARGV.include?('--http')
  transport = FastMcp::Transports::StreamableHttpTransport.new(
    nil, server, path: '/mcp'
  )
else
  transport = FastMcp::Transports::StdioTransport.new(server)
end
```

### From Legacy RackTransport

```ruby
# Before: Legacy transport
transport = FastMcp::Transports::RackTransport.new(
  app, server,
  path_prefix: '/mcp'
)

# After: StreamableHTTP
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  path: '/mcp'
)
```

### From Basic Auth to OAuth

```ruby
# Before: Simple authentication
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  app, server,
  auth_token: 'simple-token'
)

# After: OAuth 2.1
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  opaque_token_validator: method(:validate_oauth_token)
)
```

## Performance Optimization

### HTTP Transport Tuning

```ruby
# Optimized for high throughput
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  # Connection pooling
  max_sessions_per_client: 10,
  session_timeout: 3600,
  
  # Performance tuning
  json_parser: :oj,  # Use faster JSON parser
  keep_alive_timeout: 300,
  
  # Memory optimization
  session_cleanup_interval: 60,
  max_cached_sessions: 1000
)
```

### OAuth Transport Tuning

```ruby
# Optimized for OAuth performance
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  # Token caching
  token_cache_ttl: 300,
  token_cache_size: 1000,
  
  # JWT optimization
  jwt_cache_enabled: true,
  jwks_cache_ttl: 3600,
  
  # Connection reuse
  oauth_client_pool_size: 10,
  oauth_timeout: 5
)
```

## Monitoring and Observability

### Transport-Specific Metrics

```ruby
# Metrics collection for all transports
class TransportMetrics
  def self.configure_for_transport(transport_type)
    case transport_type
    when :stdio
      monitor_stdio_metrics
    when :streamable_http
      monitor_http_metrics
    when :oauth
      monitor_oauth_metrics
    end
  end
  
  def self.monitor_http_metrics
    # HTTP-specific metrics
    StatsD.gauge('mcp.transport.active_sessions')
    StatsD.timing('mcp.transport.request_duration')
    StatsD.counter('mcp.transport.requests_total')
  end
  
  def self.monitor_oauth_metrics
    # OAuth-specific metrics
    StatsD.counter('mcp.oauth.token_validations')
    StatsD.counter('mcp.oauth.scope_checks')
    StatsD.timing('mcp.oauth.validation_duration')
  end
end
```

### Health Check Endpoints

```ruby
# Transport-agnostic health checks
class HealthCheck
  def self.check_transport(transport)
    case transport
    when FastMcp::Transports::StdioTransport
      check_stdio_health(transport)
    when FastMcp::Transports::StreamableHttpTransport
      check_http_health(transport)
    when FastMcp::Transports::OAuthStreamableHttpTransport
      check_oauth_health(transport)
    end
  end
  
  def self.check_http_health(transport)
    {
      status: 'healthy',
      active_sessions: transport.session_count,
      memory_usage: transport.memory_usage,
      uptime: transport.uptime
    }
  end
  
  def self.check_oauth_health(transport)
    {
      status: 'healthy',
      oauth_server_reachable: transport.oauth_server_healthy?,
      token_cache_hit_rate: transport.token_cache_stats[:hit_rate],
      active_sessions: transport.session_count
    }
  end
end
```

## Deployment Patterns

### Single Transport Deployment

```ruby
# Dockerfile for StreamableHTTP
FROM ruby:3.1
COPY . /app
WORKDIR /app
RUN bundle install

ENV MCP_TRANSPORT=streamable_http
ENV MCP_ENDPOINT_PATH=/mcp
EXPOSE 3001

CMD ["ruby", "server.rb"]
```

### Multi-Transport Deployment

```ruby
# Support multiple transports in same application
class MultiTransportServer
  def initialize
    @server = FastMcp::Server.new(name: 'Multi-Transport Server', version: '1.0.0')
    setup_tools_and_resources
  end
  
  def start
    # STDIO for command-line usage
    if ENV['MCP_STDIO'] == 'true'
      stdio_transport = FastMcp::Transports::StdioTransport.new(@server)
      stdio_transport.start
    end
    
    # HTTP for web usage
    if ENV['MCP_HTTP'] == 'true'
      http_transport = create_http_transport
      start_http_server(http_transport)
    end
  end
  
  private
  
  def create_http_transport
    if ENV['MCP_OAUTH_ENABLED'] == 'true'
      FastMcp::Transports::OAuthStreamableHttpTransport.new(
        nil, @server,
        oauth_enabled: true,
        opaque_token_validator: method(:validate_token)
      )
    else
      FastMcp::Transports::StreamableHttpTransport.new(
        nil, @server,
        path: '/mcp'
      )
    end
  end
end
```

### Load Balancer Configuration

```nginx
# Nginx configuration for StreamableHTTP
upstream mcp_servers {
    server mcp1:3001;
    server mcp2:3001;
    server mcp3:3001;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    # SSL configuration
    ssl_certificate /etc/ssl/certs/api.example.com.crt;
    ssl_certificate_key /etc/ssl/private/api.example.com.key;
    
    # MCP endpoint
    location /mcp {
        proxy_pass http://mcp_servers;
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
}
```

## Testing Strategies

### Transport-Specific Testing

```ruby
# Test suite for multiple transports
RSpec.describe 'Transport Compatibility' do
  let(:server) { create_test_server }
  
  shared_examples 'transport functionality' do |transport|
    it 'handles basic requests' do
      response = send_request(transport, 'ping')
      expect(response['result']).to eq({})
    end
    
    it 'lists tools correctly' do
      response = send_request(transport, 'tools/list')
      expect(response['result']['tools']).to be_an(Array)
    end
  end
  
  describe 'STDIO Transport' do
    let(:transport) { FastMcp::Transports::StdioTransport.new(server) }
    include_examples 'transport functionality', :stdio
  end
  
  describe 'StreamableHTTP Transport' do
    let(:transport) { FastMcp::Transports::StreamableHttpTransport.new(nil, server) }
    include_examples 'transport functionality', :http
  end
  
  describe 'OAuth Transport' do
    let(:transport) { create_oauth_transport(server) }
    include_examples 'transport functionality', :oauth
    
    it 'enforces OAuth scopes' do
      response = send_authenticated_request(transport, 'admin/status', limited_token)
      expect(response['error']['code']).to eq(-32000)
    end
  end
end
```

### Integration Testing

```bash
#!/bin/bash
# Integration test script

# Test STDIO transport
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | ruby server.rb --stdio

# Test HTTP transport
curl -X POST http://localhost:3001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"ping","id":1}'

# Test OAuth transport
curl -X POST http://localhost:3001/mcp \
  -H "Authorization: Bearer $OAUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

## Best Practices Summary

### General Guidelines
1. **Choose the simplest transport** that meets your requirements
2. **Start with StreamableHTTP** for new HTTP applications
3. **Use OAuth only when needed** for complex authorization
4. **Monitor transport performance** and adjust configuration
5. **Plan migration paths** for transport upgrades

### Security Best Practices
1. **Always use HTTPS** in production
2. **Implement proper authentication** for public APIs
3. **Use scope-based authorization** for fine-grained control
4. **Monitor and log security events**
5. **Keep tokens and secrets secure**

### Performance Best Practices
1. **Configure appropriate timeouts**
2. **Use connection pooling** where applicable
3. **Monitor resource usage**
4. **Implement proper caching**
5. **Profile and optimize** bottlenecks

This comprehensive comparison should help you choose the right transport for your specific use case and requirements.