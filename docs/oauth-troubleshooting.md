# OAuth 2.1 Troubleshooting Guide

This guide helps diagnose and resolve common OAuth 2.1 issues with Fast MCP servers.

## Quick Diagnosis

### Step 1: Check Basic Configuration

```ruby
# Run this in your Rails console or Ruby script
transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(app, server, your_config)

puts "OAuth enabled: #{transport.oauth_enabled}"
puts "HTTPS required: #{transport.require_https}"
puts "Resource identifier: #{transport.resource_identifier}"
puts "Scopes: #{transport.scope_requirements}"
```

### Step 2: Test Token Validation

```ruby
# Test your token validator
token = "your_test_token"
validator = FastMcp::OAuth::TokenValidator.new(logger: Logger.new(STDOUT, level: Logger::DEBUG))

result = validator.validate_token(token)
puts "Token valid: #{result}"

claims = validator.extract_claims(token)
puts "Token claims: #{claims}"
```

### Step 3: Verify Connectivity

```ruby
# Test JWKS endpoint (if using JWT)
require 'net/http'

jwks_uri = "https://your-auth-server.com/.well-known/jwks.json"
response = Net::HTTP.get_response(URI(jwks_uri))

puts "JWKS Status: #{response.code}"
puts "JWKS Body: #{response.body}" if response.code == '200'
```

## Common Error Messages

### ❌ "Missing authentication token"

**Error Response:**
```json
{
  "error": "invalid_token",
  "error_description": "Missing authentication token"
}
```

**Causes & Solutions:**

1. **Missing Authorization Header**
   ```bash
   # ❌ Missing header
   curl -X POST http://localhost:3001/mcp
   
   # ✅ Correct usage
   curl -H "Authorization: Bearer your_token" -X POST http://localhost:3001/mcp
   ```

2. **Incorrect Header Format**
   ```bash
   # ❌ Wrong format
   curl -H "Authorization: your_token" -X POST http://localhost:3001/mcp
   
   # ✅ Correct format
   curl -H "Authorization: Bearer your_token" -X POST http://localhost:3001/mcp
   ```

3. **Empty Token**
   ```ruby
   # Check token extraction
   auth_header = request.headers['Authorization']
   puts "Auth header: '#{auth_header}'"
   
   token = auth_header&.sub(/^Bearer /, '')
   puts "Extracted token: '#{token}'"
   ```

### ❌ "Invalid or expired token"

**Error Response:**
```json
{
  "error": "invalid_token", 
  "error_description": "Invalid or expired token"
}
```

**Diagnosis Steps:**

1. **Check Token Format**
   ```ruby
   def debug_token(token)
     puts "Token length: #{token&.length}"
     puts "Token format: #{token&.class}"
     
     if token&.include?('.')
       parts = token.split('.')
       puts "JWT parts count: #{parts.length}"
       
       if parts.length == 3
         header = JSON.parse(Base64.urlsafe_decode64(parts[0]))
         payload = JSON.parse(Base64.urlsafe_decode64(parts[1]))
         
         puts "JWT header: #{header}"
         puts "JWT payload: #{payload}"
         puts "Expires at: #{Time.at(payload['exp']) if payload['exp']}"
         puts "Current time: #{Time.now}"
       end
     else
       puts "Opaque token format"
     end
   rescue => e
     puts "Token parsing error: #{e.message}"
   end
   
   debug_token("your_token_here")
   ```

2. **Verify Opaque Token Validator**
   ```ruby
   # Test your validator directly
   validator = lambda do |token|
     puts "Validating token: #{token}"
     
     result = {
       valid: token == 'admin_token_123',
       scopes: ['mcp:admin', 'mcp:resources', 'mcp:tools'],
       subject: 'test_user'
     }
     
     puts "Validation result: #{result}"
     result
   end
   
   # Test
   result = validator.call('admin_token_123')
   puts "Test result: #{result}"
   ```

3. **Check JWT Configuration**
   ```ruby
   # Verify JWKS accessibility
   def test_jwks_connectivity(jwks_uri)
     response = Net::HTTP.get_response(URI(jwks_uri))
     
     puts "JWKS Response: #{response.code} #{response.message}"
     
     if response.code == '200'
       jwks = JSON.parse(response.body)
       puts "Available keys: #{jwks['keys']&.length || 0}"
       jwks['keys']&.each do |key|
         puts "  Key ID: #{key['kid']}, Type: #{key['kty']}, Algorithm: #{key['alg']}"
       end
     else
       puts "JWKS Error: #{response.body}"
     end
   rescue => e
     puts "JWKS Connection Error: #{e.message}"
   end
   
   test_jwks_connectivity("https://your-auth-server.com/.well-known/jwks.json")
   ```

### ❌ "Insufficient scope"

**Error Response:**
```json
{
  "error": "insufficient_scope",
  "error_description": "Required scope: mcp:tools"
}
```

**Diagnosis Steps:**

1. **Check Token Scopes**
   ```ruby
   # Extract scopes from token
   def check_token_scopes(token)
     if token.include?('.')
       # JWT token
       payload = JSON.parse(Base64.urlsafe_decode64(token.split('.')[1]))
       scopes = payload['scope']&.split(' ') || []
     else
       # Use your opaque token validator
       result = your_token_validator.call(token)
       scopes = result[:scopes] || []
     end
     
     puts "Token scopes: #{scopes}"
     scopes
   end
   
   token_scopes = check_token_scopes("your_token")
   required_scope = "mcp:tools"
   
   puts "Has required scope: #{token_scopes.include?(required_scope)}"
   ```

2. **Verify Scope Configuration**
   ```ruby
   # Check transport scope requirements
   transport = your_oauth_transport
   
   puts "Tools scope: #{transport.scope_requirements[:tools]}"
   puts "Resources scope: #{transport.scope_requirements[:resources]}"
   puts "Admin scope: #{transport.scope_requirements[:admin]}"
   ```

3. **Test Different Scope Combinations**
   ```ruby
   # Test with different tokens
   test_cases = [
     { token: 'admin_token_123', expected_scopes: ['mcp:admin', 'mcp:resources', 'mcp:tools'] },
     { token: 'read_token_456', expected_scopes: ['mcp:resources'] },
     { token: 'tools_token_789', expected_scopes: ['mcp:tools', 'mcp:resources'] }
   ]
   
   test_cases.each do |test_case|
     puts "\nTesting token: #{test_case[:token]}"
     
     # Make test request
     response = make_test_request('/mcp', 'tools/list', test_case[:token])
     puts "Response: #{response.code}"
     
     if response.code == '403'
       error = JSON.parse(response.body)
       puts "Error: #{error['error_description']}"
     end
   end
   ```

### ❌ "HTTPS required for OAuth requests"

**Error Response:**
```json
{
  "error": "invalid_request",
  "error_description": "HTTPS required for OAuth requests"
}
```

**Solutions:**

1. **For Development (Temporary)**
   ```ruby
   # Disable HTTPS requirement for local development
   transport = FastMcp::Transports::OAuthStreamableHttpTransport.new(
     app, server,
     oauth_enabled: true,
     require_https: false # ⚠️ Only for development!
   )
   ```

2. **For Production (Recommended)**
   ```bash
   # Use HTTPS URLs
   curl -H "Authorization: Bearer token" https://your-domain.com/mcp
   ```

3. **Check Request Headers**
   ```ruby
   def debug_https_detection(request)
     puts "Request scheme: #{request.scheme}"
     puts "HTTP_X_FORWARDED_PROTO: #{request.get_header('HTTP_X_FORWARDED_PROTO')}"
     puts "rack.url_scheme: #{request.get_header('rack.url_scheme')}"
     puts "HTTP_HOST: #{request.get_header('HTTP_HOST')}"
     puts "SERVER_NAME: #{request.get_header('SERVER_NAME')}"
     
     # Check if detected as localhost
     host = request.get_header('HTTP_HOST') || request.get_header('SERVER_NAME')
     localhost_patterns = [
       /\Alocalhost(:\d+)?\z/,
       /\A127\.0\.0\.1(:\d+)?\z/,
       /\A\[::1\](:\d+)?\z/
     ]
     
     is_localhost = localhost_patterns.any? { |pattern| host&.match?(pattern) }
     puts "Detected as localhost: #{is_localhost}"
   end
   ```

### ❌ "Key with kid 'xyz' not found in JWKS"

**Error Response:**
```json
{
  "error": "invalid_token",
  "error_description": "JWT verification failed: Key with kid 'xyz' not found in JWKS"
}
```

**Diagnosis Steps:**

1. **Check Token Key ID**
   ```ruby
   def check_token_kid(token)
     header = JSON.parse(Base64.urlsafe_decode64(token.split('.')[0]))
     puts "Token key ID: #{header['kid']}"
     puts "Token algorithm: #{header['alg']}"
     header['kid']
   end
   
   token_kid = check_token_kid("your_jwt_token")
   ```

2. **Verify JWKS Keys**
   ```ruby
   def check_jwks_keys(jwks_uri)
     response = Net::HTTP.get_response(URI(jwks_uri))
     jwks = JSON.parse(response.body)
     
     puts "Available keys in JWKS:"
     jwks['keys'].each do |key|
       puts "  Kid: #{key['kid']}, Algorithm: #{key['alg']}, Type: #{key['kty']}, Use: #{key['use']}"
     end
     
     jwks['keys']
   end
   
   available_keys = check_jwks_keys("https://your-auth-server.com/.well-known/jwks.json")
   puts "Token kid '#{token_kid}' available: #{available_keys.any? { |k| k['kid'] == token_kid }}"
   ```

3. **Force JWKS Cache Refresh**
   ```ruby
   # Clear JWKS cache if using custom validator
   validator = FastMcp::OAuth::TokenValidator.new(
     jwks_uri: "https://your-auth-server.com/.well-known/jwks.json",
     logger: Logger.new(STDOUT, level: Logger::DEBUG)
   )
   
   # Force cache refresh by creating new instance
   validator = FastMcp::OAuth::TokenValidator.new(
     jwks_uri: "https://your-auth-server.com/.well-known/jwks.json"
   )
   
   result = validator.validate_token("your_jwt_token")
   puts "Validation after cache refresh: #{result}"
   ```

## Network and Connectivity Issues

### DNS Resolution Problems

```bash
# Test DNS resolution
nslookup your-auth-server.com
dig your-auth-server.com

# Test connectivity
curl -I https://your-auth-server.com/.well-known/jwks.json
```

### Firewall Issues

```bash
# Test port connectivity
telnet your-auth-server.com 443
nc -zv your-auth-server.com 443

# Test HTTP/HTTPS
curl -v https://your-auth-server.com/.well-known/jwks.json
```

### SSL Certificate Problems

```bash
# Check SSL certificate
openssl s_client -connect your-auth-server.com:443 -showcerts

# Test with curl (ignore SSL for testing)
curl -k -I https://your-auth-server.com/.well-known/jwks.json
```

## Performance Issues

### Token Validation Latency

```ruby
# Measure validation performance
def benchmark_validation(token, iterations = 100)
  require 'benchmark'
  
  validator = FastMcp::OAuth::TokenValidator.new(
    jwks_uri: "https://your-auth-server.com/.well-known/jwks.json"
  )
  
  # Warm up
  validator.validate_token(token)
  
  # Benchmark
  time = Benchmark.measure do
    iterations.times { validator.validate_token(token) }
  end
  
  puts "Average validation time: #{(time.real / iterations * 1000).round(2)}ms"
end

benchmark_validation("your_jwt_token")
```

### JWKS Caching Issues

```ruby
# Monitor JWKS cache performance
class DebugTokenValidator < FastMcp::OAuth::TokenValidator
  def fetch_jwks
    puts "Fetching JWKS from #{@jwks_uri}"
    start_time = Time.now
    
    result = super
    
    elapsed = Time.now - start_time
    puts "JWKS fetch took #{(elapsed * 1000).round(2)}ms"
    
    result
  end
end

validator = DebugTokenValidator.new(
  jwks_uri: "https://your-auth-server.com/.well-known/jwks.json"
)
```

## Development Tools

### OAuth Debug Helper

```ruby
class OAuthDebugger
  def self.debug_request(request)
    puts "\n=== OAuth Debug Information ==="
    
    # Extract token
    auth_header = request.headers['Authorization']
    puts "Authorization header: #{auth_header ? 'Present' : 'Missing'}"
    
    if auth_header
      token = auth_header.sub(/^Bearer /, '')
      puts "Token format: #{token.include?('.') ? 'JWT' : 'Opaque'}"
      puts "Token length: #{token.length}"
      
      if token.include?('.')
        debug_jwt(token)
      end
    end
    
    # Check other headers
    puts "MCP-Protocol-Version: #{request.headers['MCP-Protocol-Version']}"
    puts "Content-Type: #{request.headers['Content-Type']}"
    puts "Accept: #{request.headers['Accept']}"
    
    puts "=== End Debug Information ===\n"
  end
  
  def self.debug_jwt(token)
    parts = token.split('.')
    
    if parts.length == 3
      header = JSON.parse(Base64.urlsafe_decode64(parts[0]))
      payload = JSON.parse(Base64.urlsafe_decode64(parts[1]))
      
      puts "JWT Header: #{header}"
      puts "JWT Algorithm: #{header['alg']}"
      puts "JWT Key ID: #{header['kid']}"
      
      puts "JWT Subject: #{payload['sub']}"
      puts "JWT Issuer: #{payload['iss']}"
      puts "JWT Audience: #{payload['aud']}"
      puts "JWT Scopes: #{payload['scope']}"
      puts "JWT Expires: #{Time.at(payload['exp']) if payload['exp']}"
      puts "JWT Current Time: #{Time.now}"
      puts "JWT Expired: #{payload['exp'] && payload['exp'] < Time.now.to_i}"
    end
  rescue => e
    puts "JWT Debug Error: #{e.message}"
  end
end

# Use in your application
OAuthDebugger.debug_request(request)
```

### Test Token Generator

```ruby
class TestTokenGenerator
  def self.generate_jwt(payload = {}, secret = 'test-secret')
    require 'jwt'
    
    default_payload = {
      sub: 'test-user',
      iss: 'test-issuer',
      aud: 'test-audience',
      exp: 1.hour.from_now.to_i,
      iat: Time.now.to_i,
      scope: 'mcp:resources mcp:tools mcp:admin'
    }
    
    JWT.encode(default_payload.merge(payload), secret, 'HS256')
  end
  
  def self.generate_expired_jwt
    generate_jwt(exp: 1.hour.ago.to_i)
  end
  
  def self.generate_invalid_audience_jwt
    generate_jwt(aud: 'wrong-audience')
  end
  
  def self.generate_no_scope_jwt
    generate_jwt(scope: '')
  end
end

# Generate test tokens
puts "Valid token: #{TestTokenGenerator.generate_jwt}"
puts "Expired token: #{TestTokenGenerator.generate_expired_jwt}"
puts "Wrong audience: #{TestTokenGenerator.generate_invalid_audience_jwt}"
```

### Integration Test Helper

```ruby
# spec/support/oauth_test_helper.rb
module OAuthTestHelper
  def make_oauth_request(method, path, token, body = nil)
    headers = {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'MCP-Protocol-Version' => '2025-06-18'
    }
    
    case method.to_s.downcase
    when 'get'
      get path, headers: headers
    when 'post'
      post path, params: body&.to_json, headers: headers
    when 'put'
      put path, params: body&.to_json, headers: headers
    when 'delete'
      delete path, headers: headers
    end
    
    {
      status: response.status,
      body: response.body,
      headers: response.headers,
      json: response.content_type&.include?('json') ? JSON.parse(response.body) : nil
    }
  rescue JSON::ParserError
    {
      status: response.status,
      body: response.body,
      headers: response.headers,
      json: nil
    }
  end
  
  def expect_oauth_error(response, error_type)
    expect(response[:status]).to be >= 400
    expect(response[:json]['error']).to eq(error_type)
  end
  
  def expect_oauth_success(response)
    expect(response[:status]).to be < 400
    expect(response[:json]).to have_key('result')
  end
end

# Usage in tests
RSpec.describe 'OAuth API' do
  include OAuthTestHelper
  
  it 'rejects invalid tokens' do
    response = make_oauth_request(:post, '/mcp', 'invalid_token', {
      jsonrpc: '2.0',
      method: 'tools/list',
      id: 1
    })
    
    expect_oauth_error(response, 'invalid_token')
  end
end
```

---

For more information, see the [OAuth Configuration Guide](oauth-configuration-guide.md) and check the [examples directory](../examples/) for working implementations.