# Security Configuration Guide

## Overview

Fast MCP provides comprehensive security features for protecting your MCP servers. This guide covers all security configurations available in the StreamableHTTP transport, including authentication, authorization, and network security.

## Security Layers

### 1. Network Security
- IP address restrictions
- Origin header validation
- DNS rebinding protection
- HTTPS enforcement

### 2. Authentication
- Token-based authentication
- OAuth 2.1 integration
- JWT validation
- Opaque token support

### 3. Authorization
- Scope-based access control
- Method-level permissions
- Resource-level filtering

### 4. Protocol Security
- Version enforcement
- Secure session management
- Request validation

## Network Security Configuration

### IP Address Restrictions

Restrict connections to specific IP addresses:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  localhost_only: true,  # Default: only allow localhost
  allowed_ips: [
    '127.0.0.1',         # IPv4 localhost
    '::1',               # IPv6 localhost
    '::ffff:127.0.0.1',  # IPv4-mapped IPv6 localhost
    '10.0.0.0/24',       # Private network range
    '192.168.1.100'      # Specific IP
  ]
)
```

### Origin Header Validation

Prevent DNS rebinding attacks:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  allowed_origins: [
    'localhost',
    '127.0.0.1',
    '[::1]',
    'app.example.com',
    'api.mycompany.com',
    /\.example\.com$/,    # Regex patterns supported
    /^https:\/\/.*\.safe\.domain$/
  ]
)
```

### HTTPS Enforcement

Force HTTPS connections in production:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  require_https: Rails.env.production?,  # HTTPS required in production
  oauth_enabled: true
)

# Custom HTTPS validation
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  https_enforcer: lambda do |request|
    # Custom logic for HTTPS validation
    return true if request.ssl?
    return true if request.host == 'localhost'
    false
  end
)
```

## Authentication Configuration

### Basic Token Authentication

Simple token-based authentication:

```ruby
transport = FastMcp::Transports::AuthenticatedStreamableHttpTransport.new(
  app, server,
  auth_token: ENV['MCP_AUTH_TOKEN'],
  auth_header_name: 'Authorization',  # Default header
  auth_exempt_paths: [               # Skip auth for these paths
    '/health',
    '/status',
    '/metrics'
  ]
)
```

#### Environment Setup

```bash
# .env
MCP_AUTH_TOKEN=your-super-secret-token-here

# Generate secure tokens
ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"
```

#### Client Usage

```bash
# Include token in requests
curl -H "Authorization: Bearer your-token" \
     -X POST http://localhost:3001/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### OAuth 2.1 Authentication

Full OAuth 2.1 implementation with scope-based authorization:

```ruby
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  oauth_enabled: true,
  require_https: true,
  
  # JWT validation
  issuer: 'https://auth.example.com',
  audience: 'mcp-api',
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  
  # Opaque token validation
  opaque_token_validator: method(:validate_opaque_token),
  
  # Scope requirements
  tools_scope: 'mcp:tools',
  resources_scope: 'mcp:read',
  admin_scope: 'mcp:admin'
)
```

#### Opaque Token Validator

```ruby
def validate_opaque_token(token)
  # Call your OAuth server's introspection endpoint
  response = HTTParty.post(
    'https://auth.example.com/oauth/introspect',
    body: { token: token },
    headers: { 'Authorization' => "Basic #{client_credentials}" }
  )
  
  if response.success? && response['active']
    {
      valid: true,
      scopes: response['scope'].split(' '),
      subject: response['sub'],
      client_id: response['client_id'],
      expires_at: Time.at(response['exp'])
    }
  else
    { valid: false }
  end
rescue StandardError => e
  Rails.logger.error("Token validation failed: #{e.message}")
  { valid: false }
end
```

#### JWT Token Validation

```ruby
# For JWT tokens, configure the validator
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  # JWT configuration
  issuer: 'https://auth.example.com',
  audience: 'mcp-api',
  jwks_uri: 'https://auth.example.com/.well-known/jwks.json',
  
  # Additional JWT validation options
  clock_skew: 60,  # Allow 60 seconds clock skew
  required_scopes: ['mcp:read']  # Default required scopes
)
```

## Authorization Configuration

### Scope-Based Access Control

Define granular permissions using OAuth scopes:

```ruby
# Standard MCP scopes
DEFAULT_SCOPES = {
  'mcp:read' => 'Read access to MCP resources',
  'mcp:write' => 'Write access to MCP resources', 
  'mcp:tools' => 'Access to execute MCP tools',
  'mcp:admin' => 'Administrative access to MCP server'
}

# Custom scopes
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  custom_scopes: {
    'files:read' => 'Read file contents',
    'files:write' => 'Modify file contents',
    'system:admin' => 'System administration',
    'analytics:view' => 'View analytics data'
  },
  
  # Map operations to scopes
  tools_scope: 'mcp:tools',
  resources_scope: 'files:read',
  admin_scope: 'system:admin'
)
```

### Method-Level Authorization

Configure which scopes are required for specific MCP methods:

```ruby
class CustomOAuthTransport < FastMcp::Transports::OAuthStreamableHttpTransport
  private
  
  def determine_required_scope(parsed_request)
    method = parsed_request['method']
    
    case method
    when 'tools/list', 'tools/call'
      'mcp:tools'
    when 'resources/list'
      'mcp:read'
    when 'resources/read'
      determine_resource_scope(parsed_request['params'])
    when 'admin/status', 'admin/restart'
      'system:admin'
    when /^analytics\//
      'analytics:view'
    else
      'mcp:admin'  # Default to admin for unknown methods
    end
  end
  
  def determine_resource_scope(params)
    uri = params&.dig('uri')
    case uri
    when /^file:\/\/\/sensitive\//
      'files:admin'
    when /^file:\/\//
      'files:read'
    else
      'mcp:read'
    end
  end
end
```

### Resource-Level Filtering

Filter resources based on user permissions:

```ruby
server.filter_resources do |resources, request|
  # Get OAuth token info from headers
  oauth_scopes = request.headers['oauth-scopes']&.split(' ') || []
  
  resources.select do |resource|
    case resource.uri
    when /^file:\/\/\/public\//
      true  # Public files - no scope required
    when /^file:\/\/\/private\//
      oauth_scopes.include?('files:admin')
    when /^database:/
      oauth_scopes.include?('db:read')
    else
      oauth_scopes.include?('mcp:read')
    end
  end
end
```

## Protocol Security

### Version Enforcement

Ensure clients use the correct MCP protocol version:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  enforce_protocol_version: true,  # Default: true
  supported_versions: ['2025-06-18']  # Supported versions
)
```

#### Custom Version Validation

```ruby
class VersionEnforcedTransport < FastMcp::Transports::StreamableHttpTransport
  private
  
  def validate_protocol_version(headers)
    version = headers['mcp-protocol-version']
    
    # Allow missing version for backward compatibility
    return true if version.nil? || version.empty?
    
    # Custom validation logic
    case version
    when '2025-06-18'
      true
    when '2024-11-05'
      @logger.warn("Deprecated protocol version: #{version}")
      true  # Allow but warn
    else
      @logger.error("Unsupported protocol version: #{version}")
      false
    end
  end
end
```

### Session Security

Configure secure session management:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  session_timeout: 1800,        # 30 minutes
  session_id_entropy: 256,      # Bits of entropy for session IDs
  max_sessions_per_client: 5,   # Limit sessions per IP
  session_cleanup_interval: 300  # Clean up expired sessions every 5 min
)
```

## Security Headers

### Response Headers

Add security headers to all responses:

```ruby
class SecureTransport < FastMcp::Transports::StreamableHttpTransport
  private
  
  def add_security_headers(headers)
    headers.merge!(
      'X-Content-Type-Options' => 'nosniff',
      'X-Frame-Options' => 'DENY',
      'X-XSS-Protection' => '1; mode=block',
      'Referrer-Policy' => 'strict-origin-when-cross-origin',
      'Content-Security-Policy' => "default-src 'none'",
      'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'
    )
  end
  
  def handle_json_rpc_response(response, request)
    status, headers, body = super
    add_security_headers(headers)
    [status, headers, body]
  end
end
```

### CORS Configuration

Configure Cross-Origin Resource Sharing:

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  cors_enabled: true,
  cors_origins: [
    'https://app.example.com',
    'https://admin.example.com'
  ],
  cors_methods: ['GET', 'POST', 'OPTIONS'],
  cors_headers: [
    'Content-Type',
    'Authorization', 
    'MCP-Protocol-Version'
  ],
  cors_max_age: 86400  # 24 hours
)
```

## Production Security Checklist

### Infrastructure
- [ ] HTTPS enforced for all connections
- [ ] TLS 1.2+ required
- [ ] Valid SSL certificates installed
- [ ] IP restrictions configured
- [ ] Load balancer security configured

### Authentication & Authorization
- [ ] Strong authentication tokens (256+ bits entropy)
- [ ] OAuth 2.1 properly configured
- [ ] JWT validation working
- [ ] Scope-based authorization implemented
- [ ] Token expiration configured

### Network Security
- [ ] Origin header validation enabled
- [ ] DNS rebinding protection active
- [ ] Firewall rules configured
- [ ] VPN/private network access only (if required)

### Monitoring & Logging
- [ ] Security events logged
- [ ] Failed authentication attempts monitored
- [ ] Rate limiting implemented
- [ ] Intrusion detection configured

### Application Security
- [ ] Protocol version enforcement active
- [ ] Security headers added
- [ ] Input validation implemented
- [ ] Error messages don't leak information

## Security Testing

### Authentication Testing

```ruby
RSpec.describe 'Authentication Security' do
  it 'rejects requests without tokens' do
    post '/mcp', params: {}, headers: {}
    expect(response).to have_http_status(401)
  end
  
  it 'rejects invalid tokens' do
    post '/mcp', 
         params: { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json,
         headers: { 
           'Content-Type' => 'application/json',
           'Authorization' => 'Bearer invalid-token'
         }
    expect(response).to have_http_status(401)
  end
  
  it 'accepts valid tokens' do
    post '/mcp',
         params: { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json,
         headers: {
           'Content-Type' => 'application/json',
           'Authorization' => "Bearer #{valid_token}"
         }
    expect(response).to have_http_status(200)
  end
end
```

### Authorization Testing

```ruby
RSpec.describe 'Authorization Security' do
  it 'enforces scope requirements' do
    token_with_read_scope = generate_token(scopes: ['mcp:read'])
    
    post '/mcp',
         params: { jsonrpc: '2.0', method: 'tools/call', id: 1 }.to_json,
         headers: {
           'Authorization' => "Bearer #{token_with_read_scope}"
         }
    
    expect(response).to have_http_status(403)
    expect(JSON.parse(response.body)['error']['message']).to include('insufficient_scope')
  end
end
```

### Penetration Testing

```bash
# Test for common vulnerabilities
nmap -sS -O target_host
nikto -h http://target_host:3001

# Test authentication bypass
curl -X POST http://target_host:3001/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"admin/status","id":1}'

# Test authorization bypass
curl -X POST http://target_host:3001/mcp \
     -H "Authorization: Bearer low-privilege-token" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"admin/restart","id":1}'
```

## Security Monitoring

### Log Configuration

```ruby
# Configure security logging
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
  app, server,
  security_logger: Logger.new('log/security.log'),
  log_level: :info,
  log_failed_auth: true,
  log_successful_auth: false,  # Don't log successful auths for privacy
  log_authorization_failures: true
)
```

### Metrics Collection

```ruby
# Collect security metrics
class SecurityMetrics
  def self.record_auth_failure(reason, ip_address)
    StatsD.increment('mcp.auth.failure', tags: [
      "reason:#{reason}",
      "ip:#{ip_address}"
    ])
  end
  
  def self.record_auth_success(user_id, scopes)
    StatsD.increment('mcp.auth.success', tags: [
      "user:#{user_id}",
      "scopes:#{scopes.join(',')}"
    ])
  end
end
```

### Alerting Rules

```yaml
# Prometheus alerting rules
groups:
  - name: mcp-security
    rules:
      - alert: HighAuthFailureRate
        expr: rate(mcp_auth_failure_total[5m]) > 10
        labels:
          severity: warning
        annotations:
          summary: High authentication failure rate detected
          
      - alert: UnauthorizedAdminAccess
        expr: increase(mcp_auth_failure_total{reason="insufficient_scope",method="admin"}[1m]) > 0
        labels:
          severity: critical
        annotations:
          summary: Unauthorized admin access attempted
```

## Incident Response

### Security Incident Playbook

1. **Detection**
   - Monitor logs for unusual patterns
   - Set up alerts for security events
   - Regular security scans

2. **Response**
   - Isolate affected systems
   - Revoke compromised tokens
   - Update authentication credentials
   - Notify stakeholders

3. **Recovery**
   - Apply security patches
   - Update configurations
   - Restore services
   - Verify security posture

4. **Post-Incident**
   - Document lessons learned
   - Update security policies
   - Improve monitoring
   - Conduct training

### Emergency Token Revocation

```ruby
# Emergency token revocation
class EmergencyRevocation
  def self.revoke_all_tokens
    # Update revocation list
    TokenRevocationList.add_all_active_tokens
    
    # Clear server-side sessions
    SessionStore.clear_all
    
    # Notify monitoring systems
    SecurityMetrics.record_emergency_revocation
  end
  
  def self.revoke_user_tokens(user_id)
    tokens = TokenStore.find_by_user(user_id)
    tokens.each { |token| TokenRevocationList.add(token.jti) }
  end
end
```

This comprehensive security configuration guide ensures your MCP server is properly protected against common threats while maintaining usability and performance.