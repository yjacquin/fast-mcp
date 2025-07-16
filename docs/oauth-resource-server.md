# OAuth 2.1 Resource Server Implementation Guide

This guide covers Fast MCP's implementation as an OAuth 2.1 Resource Server, providing secure access to MCP services through standards-based token validation.

## Table of Contents

- [Overview](#overview)
- [RFC Compliance](#rfc-compliance)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Protected Resource Metadata](#protected-resource-metadata)
- [Token Validation](#token-validation)
- [Error Handling](#error-handling)
- [Security Considerations](#security-considerations)
- [Testing and Validation](#testing-and-validation)
- [Production Deployment](#production-deployment)

## Overview

Fast MCP operates as an **OAuth 2.1 Resource Server** that validates access tokens and serves protected MCP resources. This implementation focuses exclusively on the resource server role and does not include authorization server functionality.

### Key Features

- **RFC 9728 Compliant**: Protected resource metadata endpoint
- **OAuth 2.1 Security**: Audience binding, HTTPS enforcement, secure token handling
- **JWT and Opaque Token Support**: Flexible token validation strategies
- **Scope-based Authorization**: Fine-grained access control for MCP operations
- **Enhanced Error Responses**: WWW-Authenticate headers with resource metadata URLs

### What Fast MCP Does (Resource Server)

✅ **Validates Access Tokens** - Verifies signatures, expiration, and audience claims  
✅ **Enforces Authorization** - Scope-based access control for MCP operations  
✅ **Serves Protected Resources** - Secure access to tools and resources  
✅ **Provides Resource Metadata** - RFC 9728 discovery endpoint  
✅ **Error Handling** - OAuth 2.1 compliant error responses  

### What Fast MCP Does NOT Do (Authorization Server Functions)

❌ **Issue Access Tokens** - Tokens are issued by external authorization servers  
❌ **Handle Authorization Flows** - No OAuth authorization code or implicit flows  
❌ **Client Registration** - Dynamic client registration is handled externally  
❌ **Authorization Server Discovery** - Clients discover authorization servers independently  

## RFC Compliance

Fast MCP implements the following OAuth 2.1 and related RFCs:

| RFC | Title | Implementation | Status |
|-----|-------|----------------|--------|
| [RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749) | OAuth 2.0 Authorization Framework | Resource Server components | ✅ Complete |
| [RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519) | JSON Web Token (JWT) | JWT validation with JWKS | ✅ Complete |
| [RFC 7662](https://datatracker.ietf.org/doc/html/rfc7662) | Token Introspection | Local token validation | ✅ Complete |
| [RFC 8707](https://datatracker.ietf.org/doc/html/rfc8707) | Resource Indicators | Audience binding | ✅ Complete |
| [RFC 9728](https://datatracker.ietf.org/doc/html/rfc9728) | Protected Resource Metadata | Discovery endpoint | ✅ Complete |
| [OAuth 2.1](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-12) | OAuth 2.1 Security Best Practices | Resource server requirements | ✅ Complete |

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│ Authorization   │    │   MCP Client    │    │  Fast MCP       │
│ Server          │    │                 │    │  Resource       │
│                 │    │                 │    │  Server         │
│ - Issues tokens │    │ - Gets tokens   │    │ - Validates     │
│ - Authenticates │    │ - Makes         │    │   tokens        │
│   users         │    │   requests      │    │ - Serves MCP    │
│ - Manages       │────┤                 │────┤   resources     │
│   scopes        │    │                 │    │ - Enforces      │
│                 │    │                 │    │   authorization │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                        │                        │
        │                        │                        │
        └────────────────────────┼────────────────────────┘
                                 │
            ┌─────────────────────▼─────────────────────┐
            │    Protected Resource Metadata            │
            │    /.well-known/oauth-protected-resource  │
            │                                           │
            │    - Discovery endpoint                   │
            │    - Lists authorization servers          │
            │    - Resource identifier                  │
            └───────────────────────────────────────────┘
```

### Request Flow

1. **Client Authentication**: Client obtains access token from authorization server
2. **Token Presentation**: Client includes token in Authorization header: `Bearer <token>`
3. **Token Validation**: Fast MCP validates token signature, expiration, and audience
4. **Scope Authorization**: System checks required scopes for the requested operation
5. **Resource Access**: If authorized, client can access MCP tools and resources
6. **Error Handling**: Invalid/insufficient tokens receive OAuth 2.1 compliant error responses

## Configuration

### Basic Setup

```ruby
require 'fast_mcp'

# Create MCP server
server = FastMcp::Server.new(name: 'My MCP Service', version: '1.0.0')

# Configure OAuth resource server
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, # Your Rack application
  server,
  
  # OAuth Configuration
  oauth_enabled: true,
  require_https: true, # Required in production
  
  # Resource Identity (MUST match audience in tokens)
  resource_identifier: 'https://api.example.com/mcp',
  
  # Authorization Servers
  authorization_servers: [
    'https://auth.example.com',
    'https://backup-auth.example.com'
  ],
  
  # Token Validation
  opaque_token_validator: method(:validate_opaque_token),
  
  # Scope Requirements
  tools_scope: 'mcp:tools',
  resources_scope: 'mcp:resources',
  admin_scope: 'mcp:admin'
)
```

### JWT Token Configuration

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  
  # JWT Configuration
  jwt_algorithm: 'RS256',
  jwt_audience: 'https://api.example.com/mcp',
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  
  # Security
  require_https: true,
  clock_skew_tolerance: 60, # seconds
  
  # Authorization Servers
  authorization_servers: ['https://auth.example.com']
)
```

### Environment-based Configuration

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  
  # Environment-driven configuration
  oauth_enabled: ENV.fetch('OAUTH_ENABLED', 'true') == 'true',
  require_https: ENV.fetch('REQUIRE_HTTPS', Rails.env.production?.to_s) == 'true',
  resource_identifier: ENV.fetch('OAUTH_RESOURCE_IDENTIFIER'),
  authorization_servers: ENV.fetch('OAUTH_AUTHORIZATION_SERVERS', '').split(','),
  
  # JWT from environment
  jwks_uri: ENV['OAUTH_JWKS_URI'],
  jwt_audience: ENV['OAUTH_JWT_AUDIENCE'],
  jwt_algorithm: ENV.fetch('OAUTH_JWT_ALGORITHM', 'RS256')
)
```

## Protected Resource Metadata

Fast MCP automatically provides a protected resource metadata endpoint as specified in RFC 9728.

### Endpoint

```
GET /.well-known/oauth-protected-resource
```

### Response Format

```json
{
  "resource": "https://api.example.com/mcp",
  "authorization_servers": [
    "https://auth.example.com",
    "https://backup-auth.example.com"
  ]
}
```

### Response Headers

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: public, max-age=3600
```

### Usage by Clients

Clients can discover authorization servers automatically:

```javascript
// Client-side discovery
async function discoverAuthServers(resourceUrl) {
  const metadataUrl = `${resourceUrl}/.well-known/oauth-protected-resource`;
  const response = await fetch(metadataUrl);
  const metadata = await response.json();
  
  return metadata.authorization_servers;
}

// Usage
const authServers = await discoverAuthServers('https://api.example.com');
// Returns: ['https://auth.example.com', 'https://backup-auth.example.com']
```

### Configuration Options

```ruby
# Minimal configuration (empty authorization servers array)
authorization_servers: []

# Single authorization server
authorization_servers: ['https://auth.example.com']

# Multiple authorization servers for redundancy
authorization_servers: [
  'https://primary-auth.example.com',
  'https://backup-auth.example.com',
  'https://disaster-recovery-auth.example.com'
]
```

## Token Validation

### JWT Token Validation

Fast MCP validates JWT tokens according to RFC 7519:

```ruby
# JWT validation process
def validate_jwt_token(token)
  # 1. Parse JWT structure
  header, payload, signature = parse_jwt(token)
  
  # 2. Verify signature using JWKS
  verify_signature(header, payload, signature)
  
  # 3. Validate standard claims
  validate_expiration(payload['exp'])
  validate_not_before(payload['nbf'])
  validate_issued_at(payload['iat'])
  
  # 4. Validate audience (critical for security)
  validate_audience(payload['aud'], @resource_identifier)
  
  # 5. Extract scopes
  scopes = extract_scopes(payload)
  
  {
    valid: true,
    subject: payload['sub'],
    scopes: scopes,
    expires_at: Time.at(payload['exp'])
  }
end
```

### Opaque Token Validation

For opaque tokens, implement a custom validator:

```ruby
def validate_opaque_token(token)
  # Your validation logic (database lookup, cache check, etc.)
  user = TokenStore.find_by_token(token)
  
  return { valid: false } unless user&.token_valid?
  
  {
    valid: true,
    subject: user.id,
    scopes: user.scopes,
    expires_at: user.token_expires_at
  }
end

# Configure transport with opaque validator
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  opaque_token_validator: method(:validate_opaque_token)
)
```

### Token Extraction

Tokens are extracted according to OAuth 2.1 security requirements:

```ruby
# ✅ Accepted: Authorization header with Bearer scheme
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...

# ❌ Rejected: Query parameters (security risk)
GET /mcp?access_token=eyJhbGciOiJSUzI1NiIs...

# ❌ Rejected: Form-encoded body (not applicable to MCP)
access_token=eyJhbGciOiJSUzI1NiIs...
```

## Error Handling

Fast MCP provides OAuth 2.1 compliant error responses with enhanced WWW-Authenticate headers.

### Missing Token

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="mcp-server", 
                  resource_metadata="https://api.example.com/.well-known/oauth-protected-resource"
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Missing authentication token"
  },
  "id": null
}
```

### Invalid Token

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="invalid_token", 
                  error_description="The access token is invalid or expired",
                  resource_metadata="https://api.example.com/.well-known/oauth-protected-resource"
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Invalid or expired token"
  },
  "id": null
}
```

### Insufficient Scope

```http
HTTP/1.1 403 Forbidden
WWW-Authenticate: Bearer error="insufficient_scope", 
                  scope="mcp:tools",
                  resource_metadata="https://api.example.com/.well-known/oauth-protected-resource"
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "error": {
    "code": -32002,
    "message": "Required scope: mcp:tools"
  },
  "id": null
}
```

### Wrong Audience

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="invalid_token", 
                  error_description="Token audience does not match resource server",
                  resource_metadata="https://api.example.com/.well-known/oauth-protected-resource"
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "error": {
    "code": -32001,
    "message": "Token not intended for this resource server"
  },
  "id": null
}
```

## Security Considerations

### Audience Validation

**Critical**: Always validate the audience claim to prevent confused deputy attacks:

```ruby
# ✅ Correct: Exact audience matching
def validate_audience(token_audience, resource_identifier)
  return false unless token_audience == resource_identifier
  true
end

# ❌ Dangerous: Wildcard or substring matching
def validate_audience_insecure(token_audience, resource_identifier)
  return false unless token_audience.include?(resource_identifier) # DON'T DO THIS
  true
end
```

### HTTPS Enforcement

```ruby
# ✅ Production configuration
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  require_https: true, # Enforced in production
  oauth_enabled: true
)

# ⚠️ Development only
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  require_https: false, # Only for localhost development
  oauth_enabled: true
)
```

### Token Security

- **No Token Logging**: Tokens are never logged or exposed in error messages
- **Secure Headers Only**: Tokens accepted only via Authorization header
- **No Token Passthrough**: Tokens are never forwarded to other services
- **Minimal Token Storage**: Tokens are validated and discarded immediately

### Clock Skew Tolerance

```ruby
# Configure clock skew tolerance for distributed systems
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  clock_skew_tolerance: 60, # Allow 60 seconds of clock drift
  jwt_algorithm: 'RS256'
)
```

## Testing and Validation

### Manual Testing

```bash
# 1. Test protected resource metadata endpoint
curl -X GET https://api.example.com/.well-known/oauth-protected-resource \
  -H "Accept: application/json"

# Expected: 200 OK with authorization_servers array

# 2. Test without authentication
curl -X POST https://api.example.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Expected: 401 Unauthorized with WWW-Authenticate header

# 3. Test with valid token
curl -X POST https://api.example.com/mcp \
  -H "Authorization: Bearer <valid-token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Expected: 200 OK with tools list

# 4. Test with insufficient scope
curl -X POST https://api.example.com/mcp \
  -H "Authorization: Bearer <read-only-token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"admin_tool"},"id":1}'

# Expected: 403 Forbidden with insufficient_scope error
```

### Automated Testing

```ruby
RSpec.describe 'OAuth 2.1 Resource Server' do
  let(:transport) { create_oauth_transport }
  
  describe 'protected resource metadata' do
    it 'serves metadata endpoint' do
      response = get '/.well-known/oauth-protected-resource'
      
      expect(response.status).to eq(200)
      expect(response.content_type).to eq('application/json')
      
      metadata = JSON.parse(response.body)
      expect(metadata['resource']).to eq('https://api.example.com/mcp')
      expect(metadata['authorization_servers']).to be_an(Array)
    end
  end
  
  describe 'token validation' do
    it 'accepts valid JWT tokens' do
      token = create_valid_jwt_token(audience: 'https://api.example.com/mcp')
      
      response = post '/mcp',
        headers: { 'Authorization' => "Bearer #{token}" },
        json: { jsonrpc: '2.0', method: 'tools/list', id: 1 }
      
      expect(response.status).to eq(200)
    end
    
    it 'rejects tokens with wrong audience' do
      token = create_valid_jwt_token(audience: 'https://other.example.com')
      
      response = post '/mcp',
        headers: { 'Authorization' => "Bearer #{token}" },
        json: { jsonrpc: '2.0', method: 'tools/list', id: 1 }
      
      expect(response.status).to eq(401)
      expect(response.headers['WWW-Authenticate']).to include('invalid_token')
    end
  end
end
```

### Load Testing

```ruby
# Test OAuth overhead under load
require 'benchmark'

def benchmark_oauth_requests(count = 1000)
  token = create_valid_jwt_token
  
  Benchmark.measure do
    count.times do
      response = post '/mcp',
        headers: { 'Authorization' => "Bearer #{token}" },
        json: { jsonrpc: '2.0', method: 'ping', id: 1 }
      
      raise 'Unexpected response' unless response.status == 200
    end
  end
end

# Run benchmark
result = benchmark_oauth_requests(1000)
puts "OAuth validation: #{result.real}s for 1000 requests"
puts "Rate: #{(1000 / result.real).round(2)} requests/second"
```

## Production Deployment

### Security Checklist

- [ ] **HTTPS Enforced**: `require_https: true` in production
- [ ] **Audience Validation**: Resource identifier matches token audience claims
- [ ] **Authorization Server Trust**: Only trusted authorization servers listed
- [ ] **Token Validation**: JWT signature verification or secure opaque token validation
- [ ] **Scope Enforcement**: Appropriate scopes required for each operation
- [ ] **Error Handling**: No sensitive information leaked in error responses
- [ ] **Monitoring**: OAuth errors and performance metrics tracked
- [ ] **Clock Synchronization**: NTP configured for accurate token expiration

### Environment Configuration

```bash
# Production environment variables
export OAUTH_ENABLED=true
export REQUIRE_HTTPS=true
export OAUTH_RESOURCE_IDENTIFIER=https://api.example.com/mcp
export OAUTH_AUTHORIZATION_SERVERS=https://auth.example.com,https://backup-auth.example.com
export OAUTH_JWKS_URI=https://auth.example.com/.well-known/jwks.json
export OAUTH_JWT_AUDIENCE=https://api.example.com/mcp
export OAUTH_JWT_ALGORITHM=RS256
```

### Monitoring and Metrics

```ruby
# OAuth-specific metrics
class OAuthMetrics
  def self.track_token_validation(success:, error_type: nil, duration:)
    StatsD.increment('oauth.token_validation.total')
    StatsD.increment("oauth.token_validation.#{success ? 'success' : 'failure'}")
    StatsD.increment("oauth.error.#{error_type}") if error_type
    StatsD.timing('oauth.token_validation.duration', duration)
  end
  
  def self.track_scope_check(method:, required_scope:, success:)
    StatsD.increment('oauth.scope_check.total')
    StatsD.increment("oauth.scope_check.#{success ? 'allowed' : 'denied'}")
    StatsD.increment("oauth.method.#{method}.total")
    StatsD.increment("oauth.scope.#{required_scope}.checked")
  end
end
```

### Health Checks

```ruby
# OAuth-aware health check
class HealthCheck
  def self.oauth_status
    {
      oauth_enabled: oauth_enabled?,
      jwks_accessible: jwks_accessible?,
      authorization_servers: authorization_servers_reachable?,
      last_token_validation: last_successful_validation
    }
  end
  
  private
  
  def self.jwks_accessible?
    return true unless ENV['OAUTH_JWKS_URI']
    
    response = Net::HTTP.get_response(URI(ENV['OAUTH_JWKS_URI']))
    response.is_a?(Net::HTTPSuccess)
  rescue
    false
  end
end
```

### Backup and Recovery

```ruby
# Graceful degradation when authorization servers are unavailable
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  
  # Fallback configuration
  fallback_mode: :read_only, # Options: :disabled, :read_only, :cached_tokens
  cache_valid_tokens: true,
  token_cache_ttl: 300, # 5 minutes
  
  # Circuit breaker for JWKS endpoint
  jwks_circuit_breaker: {
    failure_threshold: 5,
    recovery_timeout: 60,
    fallback_to_cache: true
  }
)
```

---

## Related Documentation

- [OAuth Configuration Guide](oauth-configuration-guide.md) - Complete setup and configuration
- [Security Best Practices](security.md) - General security guidelines
- [Transport Comparison](transport_comparison.md) - Choosing the right transport
- [OAuth Troubleshooting](oauth-troubleshooting.md) - Debugging OAuth issues

## Support

For implementation questions or issues:

1. Check the [OAuth Troubleshooting Guide](oauth-troubleshooting.md)
2. Review [example implementations](../examples/)
3. Open an issue on [GitHub](https://github.com/yjacquin/fast-mcp/issues)

---

*This documentation covers Fast MCP v1.0+ OAuth 2.1 Resource Server implementation. For older versions, see the migration guide.*