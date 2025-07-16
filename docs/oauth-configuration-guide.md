# OAuth 2.1 Configuration Guide for Fast MCP

This guide provides comprehensive information on configuring OAuth 2.1 authentication and authorization for Fast MCP servers.

## Table of Contents

- [Overview](#overview)
- [Security Features](#security-features)
- [Quick Start](#quick-start)
- [Configuration Options](#configuration-options)
- [Token Validation](#token-validation)
- [Protected Resource Metadata](#protected-resource-metadata)
- [Scope Management](#scope-management)
- [Security Best Practices](#security-best-practices)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)

## Overview

Fast MCP implements OAuth 2.1 (RFC 6749 + security enhancements) to provide secure, standards-based authentication and authorization for MCP servers. This implementation includes:

- **PKCE (Proof Key for Code Exchange)** - Prevents authorization code interception attacks
- **Audience Binding** - Prevents confused deputy attacks using resource parameters
- **Token Introspection** - Local token validation for resource servers
- **Protected Resource Metadata** - RFC 9728 compliant resource server discovery
- **Scope-based Authorization** - Fine-grained access control for MCP operations

## Security Features

### 🔒 Core Security Features

| Feature | Status | RFC | Description |
|---------|--------|-----|-------------|
| ✅ Audience Binding | Implemented | RFC 8707 | Prevents confused deputy attacks |
| ✅ JWT Verification | Implemented | RFC 7519 | Full signature validation with JWKS |
| ✅ Token Introspection | Implemented | RFC 7662 | Local token validation for resource servers |
| ✅ Protected Resource Metadata | Implemented | RFC 9728 | Resource server discovery and metadata |
| ✅ WWW-Authenticate Headers | Implemented | RFC 9728 | Enhanced error responses with metadata URLs |
| ✅ Standard Error Responses | Implemented | RFC 6749 | OAuth 2.1 compliant error handling |

### 🛡️ Security Enhancements

- **HTTPS Enforcement** - Required by default in production
- **Secure Token Storage** - No tokens in query strings or logs
- **Clock Skew Tolerance** - Configurable for distributed systems
- **Origin Validation** - CORS and origin checking
- **Rate Limiting Ready** - Structured for rate limiting integration

## Quick Start

### 1. Basic OAuth Server Setup

```ruby
require 'fast_mcp'

# Create MCP server
server = FastMcp::Server.new(name: 'My OAuth MCP Server', version: '1.0.0')

# Register your tools and resources
server.register_tool(MyTool)
server.register_resource(MyResource)

# Configure OAuth transport
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, # Your Rack app
  server,
  
  # OAuth Configuration
  oauth_enabled: true,
  require_https: true, # Set to false for development only
  
  # Token Validation
  opaque_token_validator: lambda do |token|
    # Your token validation logic
    user = authenticate_token(token)
    {
      valid: user.present?,
      scopes: user&.scopes || [],
      subject: user&.id
    }
  end,
  
  # Scope Configuration
  tools_scope: 'mcp:tools',
  resources_scope: 'mcp:resources',
  admin_scope: 'mcp:admin',
  
  # Security
  resource_identifier: 'https://your-domain.com/mcp',
  
  # Authorization Servers (for protected resource metadata endpoint)
  authorization_servers: [
    'https://auth.your-domain.com'
  ]
)
```

### 2. JWT Token Validation Setup

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  
  # JWT Configuration
  oauth_enabled: true,
  issuer: 'https://your-auth-server.com',
  audience: 'https://your-mcp-server.com/mcp',
  jwks_uri: 'https://your-auth-server.com/.well-known/jwks.json',
  
  # Optional: HMAC secret for shared-secret JWTs
  hmac_secret: ENV['JWT_HMAC_SECRET'],
  
  # Security settings
  require_https: true,
  resource_identifier: 'https://your-mcp-server.com/mcp'
)
```

### 3. Rails Integration

```ruby
# config/initializers/fast_mcp.rb
FastMcp.mount_in_rails(
  Rails.application,
  transport: :oauth,
  oauth_enabled: true,
  
  # Production settings
  require_https: Rails.env.production?,
  issuer: ENV['OAUTH_ISSUER'],
  audience: ENV['MCP_AUDIENCE'],
  jwks_uri: ENV['OAUTH_JWKS_URI']
)
```

## Configuration Options

### Core OAuth Settings

```ruby
{
  # OAuth Control
  oauth_enabled: true,              # Enable/disable OAuth
  require_https: true,              # Enforce HTTPS (except localhost)
  
  # Token Validation
  opaque_token_validator: proc,     # Custom token validator
  issuer: 'https://auth.example.com', # JWT issuer
  audience: 'https://api.example.com', # JWT audience
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  hmac_secret: 'secret',            # HMAC secret for shared JWTs
  
  # Introspection (for opaque tokens)
  introspection_endpoint: 'https://auth.example.com/introspect',
  client_id: 'your_client_id',
  client_secret: 'your_client_secret',
  
  # Security
  resource_identifier: 'https://api.example.com/mcp', # Audience binding
  clock_skew: 60,                   # Clock skew tolerance (seconds)
  
  # Scopes
  tools_scope: 'mcp:tools',         # Required for tool execution
  resources_scope: 'mcp:resources', # Required for resource access
  admin_scope: 'mcp:admin',         # Required for admin operations
  
  # CORS
  cors_enabled: true,
  allowed_origins: ['https://frontend.example.com']
}
```

### Environment Variables

```bash
# JWT Configuration
OAUTH_ISSUER=https://your-auth-server.com
OAUTH_JWKS_URI=https://your-auth-server.com/.well-known/jwks.json
JWT_HMAC_SECRET=your-hmac-secret
MCP_AUDIENCE=https://your-api.com/mcp

# Introspection
OAUTH_INTROSPECTION_ENDPOINT=https://your-auth-server.com/oauth/introspect
MCP_CLIENT_ID=your-mcp-client-id
MCP_CLIENT_SECRET=your-client-secret

# Security
REQUIRE_HTTPS=true
ALLOWED_ORIGINS=https://app1.com,https://app2.com
```

## Token Validation

### Option 1: JWT Tokens (Recommended)

JWT tokens provide stateless validation with built-in security features:

```ruby
# Automatic JWKS validation
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  issuer: 'https://auth.example.com',
  audience: 'https://api.example.com/mcp',
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json'
)

# With authorization server discovery
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  issuer: 'https://auth.example.com' # Auto-discovers endpoints
)
```

### Option 2: Opaque Tokens

For custom token systems or when you need database validation:

```ruby
validator = lambda do |token|
  # Query your database/cache
  token_record = Token.find_by(value: token)
  
  return { valid: false } unless token_record&.active?
  
  {
    valid: true,
    scopes: token_record.scopes,
    subject: token_record.user_id,
    client_id: token_record.client_id,
    expires_at: token_record.expires_at
  }
end

transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  opaque_token_validator: validator
)
```

### Option 3: Token Introspection

For microservices or when you want remote validation:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  introspection_endpoint: 'https://auth.example.com/oauth/introspect',
  client_id: 'mcp_server_client',
  client_secret: ENV['INTROSPECTION_SECRET']
)
```

## Protected Resource Metadata

Fast MCP implements RFC 9728 to provide a standardized way for clients to discover authorization servers and resource server metadata.

### Metadata Endpoint

The protected resource metadata endpoint is automatically available at:

```
GET /.well-known/oauth-protected-resource
```

### Configuration

Configure authorization servers that can issue tokens for your MCP server:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  resource_identifier: 'https://mcp-server.example.com',
  
  # Authorization servers that can issue tokens for this resource server
  authorization_servers: [
    'https://auth.example.com',
    'https://secondary-auth.example.com'
  ]
)
```

### Metadata Response

The endpoint returns JSON with resource server information:

```json
{
  "resource": "https://mcp-server.example.com",
  "authorization_servers": [
    "https://auth.example.com",
    "https://secondary-auth.example.com"
  ]
}
```

### Enhanced Error Responses

When OAuth authentication fails, error responses include WWW-Authenticate headers with metadata URLs:

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="invalid_token", 
                  resource_metadata="https://mcp-server.example.com/.well-known/oauth-protected-resource"
```

This allows clients to automatically discover authorization servers and retry authentication.

### Security Considerations

- **Authorization Server Trust**: Only list authorization servers you trust
- **Resource Identifier**: Must match the `aud` claim in access tokens
- **HTTPS Required**: Metadata endpoint enforces HTTPS in production
- **Public Endpoint**: The metadata endpoint is publicly accessible (no authentication required)

### Testing the Endpoint

Test the metadata endpoint with curl:

```bash
# Test metadata endpoint
curl -X GET https://your-mcp-server.com/.well-known/oauth-protected-resource \
  -H "Accept: application/json"
```

Expected response:
```json
{
  "resource": "https://your-mcp-server.com",
  "authorization_servers": ["https://auth.your-domain.com"]
}
```

## Scope Management

### Default Scopes

Fast MCP defines standard scopes for common operations:

```ruby
{
  'mcp:resources' => 'Read access to MCP resources',
  'mcp:tools'     => 'Access to execute MCP tools', 
  'mcp:admin'     => 'Administrative access to MCP server'
}
```

### Custom Scopes

Define application-specific scopes:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  
  # Custom scope mappings
  tools_scope: 'myapp:execute',
  resources_scope: 'myapp:read',
  admin_scope: 'myapp:admin',
  
  # Additional scope definitions
  custom_scopes: {
    'myapp:write' => 'Write access to application data',
    'myapp:export' => 'Export application data',
    'myapp:import' => 'Import application data'
  }
)
```

### Scope Validation in Tools

```ruby
class MyAdminTool < FastMcp::Tool
  def call(*args)
    # Access OAuth info from headers
    oauth_scopes = headers['oauth-scopes']&.split(' ') || []
    oauth_subject = headers['oauth-subject']
    
    unless oauth_scopes.include?('mcp:admin')
      return error('Insufficient privileges: admin scope required')
    end
    
    # Your tool logic here
    success(message: "Admin operation completed by user #{oauth_subject}")
  end
end
```

## Security Best Practices

### 🔐 Production Security Checklist

- [ ] **HTTPS Everywhere** - Set `require_https: true`
- [ ] **Strong Audience Binding** - Use specific `resource_identifier`
- [ ] **Scope Minimization** - Grant minimal required scopes
- [ ] **Token Rotation** - Implement short-lived tokens with refresh
- [ ] **CORS Restrictions** - Limit `allowed_origins` to specific domains
- [ ] **Rate Limiting** - Implement request rate limiting
- [ ] **Monitoring** - Log all authentication events
- [ ] **Secret Management** - Use environment variables for secrets
- [ ] **Key Rotation** - Regularly rotate HMAC secrets and keys

### 🛡️ Token Security

```ruby
# DO: Use environment variables for secrets
hmac_secret: ENV['JWT_HMAC_SECRET']

# DON'T: Hardcode secrets
hmac_secret: 'hardcoded-secret-123'

# DO: Use specific audiences
audience: 'https://api.example.com/mcp'

# DON'T: Use generic audiences  
audience: 'api'

# DO: Implement token expiration
# Token should have reasonable exp claim

# DON'T: Use long-lived tokens without refresh
```

### 🌐 HTTPS Configuration

```ruby
# Production
require_https: true

# Development & test (only when necessary)
require_https: Rails.env.local?

# Docker/container environments
require_https: ENV['REQUIRE_HTTPS'] != 'false'
```

### 🔍 Audit Logging

```ruby
# Log OAuth events for security monitoring
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  logger: Logger.new('oauth_audit.log', level: Logger::INFO)
)

# The transport automatically logs:
# - Authentication attempts
# - Authorization failures  
# - Token validation errors
# - Scope violations
```

## Troubleshooting

### Common Issues

#### 1. "Invalid or expired token" errors

**Symptoms**: Requests fail with 401 Unauthorized

**Solutions**:
```ruby
# Check token format
token = request.headers['Authorization']&.sub(/^Bearer /, '')
puts "Token format: #{token.class}, length: #{token&.length}"

# Verify JWT structure
if token&.include?('.')
  header = JSON.parse(Base64.urlsafe_decode64(token.split('.')[0]))
  puts "JWT header: #{header}"
end

# Check token expiration
validator = FastMcp::OAuth::TokenValidator.new(logger: Logger.new(STDOUT))
claims = validator.extract_claims(token)
puts "Token claims: #{claims}"
```

#### 2. "Insufficient scope" errors

**Symptoms**: Requests fail with 403 Forbidden

**Solutions**:
```ruby
# Check scope configuration
transport.scope_requirements.each do |operation, required_scope|
  puts "#{operation} requires: #{required_scope}"
end

# Verify token scopes
oauth_scopes = headers['oauth-scopes']&.split(' ') || []
puts "Token has scopes: #{oauth_scopes}"
puts "Required scope: #{required_scope}"
puts "Has required scope: #{oauth_scopes.include?(required_scope)}"
```

#### 3. JWKS validation failures

**Symptoms**: JWT tokens are rejected despite being valid

**Solutions**:
```ruby
# Test JWKS connectivity
require 'net/http'
response = Net::HTTP.get_response(URI(jwks_uri))
puts "JWKS response: #{response.code} #{response.message}"
puts "JWKS content: #{response.body}"

# Check key matching
jwks = JSON.parse(response.body)
token_header = JSON.parse(Base64.urlsafe_decode64(token.split('.')[0]))
puts "Token kid: #{token_header['kid']}"
puts "Available kids: #{jwks['keys'].map { |k| k['kid'] }}"
```

#### 4. HTTPS enforcement issues

**Symptoms**: Requests rejected with "HTTPS required"

**Solutions**:
```ruby
# Check request scheme detection
puts "Request scheme: #{request.scheme}"
puts "X-Forwarded-Proto: #{request.get_header('HTTP_X_FORWARDED_PROTO')}"
puts "Is localhost: #{localhost_request?(request)}"

# For development, disable HTTPS requirement
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  require_https: false # Only for development!
)
```

### Debug Logging

Enable detailed OAuth logging:

```ruby
# Enable debug logging
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  logger: logger
)

# This will log:
# - Token extraction attempts
# - Validation steps
# - Scope checking
# - Error details
```

### Health Checks

Implement OAuth-aware health checks:

```ruby
# Health check endpoint
get '/health' do
  content_type :json
  
  health = {
    status: 'ok',
    timestamp: Time.now.iso8601,
    oauth: {
      enabled: oauth_enabled?,
      issuer: ENV['OAUTH_ISSUER'],
      jwks_accessible: jwks_accessible?
    }
  }
  
  status 200
  health.to_json
end

def jwks_accessible?
  return true unless ENV['OAUTH_JWKS_URI']
  
  response = Net::HTTP.get_response(URI(ENV['OAUTH_JWKS_URI']))
  response.is_a?(Net::HTTPSuccess)
rescue
  false
end
```

---

For more examples and advanced configurations, see the [examples directory](../examples/).
