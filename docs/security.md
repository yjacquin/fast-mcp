# Security Features in Fast MCP

Security is a critical aspect of any application that exposes functionality through APIs, especially when those APIs can be called by AI models or external clients. Fast MCP provides several security features to help protect your applications.

## Table of Contents

- [DNS Rebinding Protection](#dns-rebinding-protection)
- [Authentication](#authentication)
  - [Enabling Authentication](#enabling-authentication)
  - [Authentication Strategies](#authentication-strategies)
    - [Token-based Authentication](#1-token-based-authentication-default)
    - [Custom Authentication Headers](#custom-authentication-headers)
    - [Proc-based Authentication](#2-proc-based-authentication)
    - [HTTP Basic Authentication](#3-http-basic-authentication)
  - [Authentication Exemptions](#authentication-exemptions)
  - [Authentication Environment Variables](#authentication-environment-variables)
- [Best Practices](#best-practices)
- [Additional Resources](#additional-resources)

## DNS Rebinding Protection

DNS rebinding attacks are a type of attack where a malicious website tricks a browser into sending requests to a local service by changing the DNS records after the page has loaded. This could allow attackers to interact with local MCP servers from remote websites.

### How Fast MCP Protects Against DNS Rebinding

Fast MCP's HTTP/SSE transport validates the `Origin` header on all incoming connections to prevent DNS rebinding attacks. This ensures that only requests from trusted origins are processed.

### Configuration

You can configure the allowed origins when creating the rack middleware:

```ruby
# Configure allowed origins (defaults to ['localhost', '127.0.0.1'])
FastMcp.rack_middleware(app, 
  allowed_origins: [
    'localhost', 
    '127.0.0.1', 
    'your-domain.com', 
    /.*\.your-domain\.com/  # Regex for subdomains
  ],
  # other options...
)
```

With the Rails integration, it defaults to `Rails.application.config.hosts`, but you can override this through the initializer:

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  ...
  # Add allowed origins below, it defaults to Rails.application.config.hosts
  allowed_origins: ['example.com', /.*\.example\.com/],
...
) do |server|
  ...
end
```
```

The `allowed_origins` parameter accepts an array of strings and regular expressions:
- Strings are matched exactly against the hostname in the Origin header
- Regular expressions are matched against the hostname for more flexible matching (e.g., for subdomains)

### Technical Implementation

When a request arrives at the MCP endpoint, the RackTransport middleware:

1. Extracts the Origin header from the request
2. Falls back to Referer or Host headers if Origin is not present
3. Parses the hostname from the header value
4. Checks if the hostname matches any of the allowed origins
5. Returns a 403 Forbidden response if the hostname is not allowed

## Authentication

Fast MCP supports multiple authentication strategies to ensure only authorized clients can access your MCP server.

### Enabling Authentication

To enable authentication, set the `authenticate` option to `true` and provide the appropriate authentication options:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    # Authentication configuration options...
  }
)
```

In Rails applications, you can enable authentication in the initializer:

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  authenticate: true,
  auth_options: {
    # Authentication configuration options...
  }
)
```

### Authentication Strategies

Fast MCP supports three authentication strategies, configured within the `auth_options` hash:

#### 1. Token-based Authentication (Default)

The simplest authentication strategy that validates a token from the request header:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :token,  # This is the default if not specified
    auth_token: 'your-secret-token',
    auth_header: 'Authorization'  # Optional, defaults to 'Authorization'
  }
)
```

You can also use environment variables for your token:
```ruby
# Set MCP_AUTH_TOKEN in your environment
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :token
    # Will use ENV['MCP_AUTH_TOKEN'] and ENV['MCP_AUTH_HEADER'] (defaults to 'Authorization')
  }
)
```

### Custom Authentication Headers

By default, Fast MCP uses the `Authorization` header for token-based authentication, but you can configure it to use any custom header. This is particularly useful for:

1. Integration with API gateway services
2. Adding an additional security layer (security through obscurity)
3. Supporting multiple authentication schemes

#### Using X-API-Key Header

A common pattern for API authentication is to use the `X-API-Key` header instead of the standard `Authorization` header:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :token,
    auth_token: 'your-secret-token',
    auth_header: 'X-API-Key'  # Use X-API-Key header instead of Authorization
  }
)
```

With this configuration, clients should send the API key directly in the header without the "Bearer" prefix:

```
X-API-Key: your-secret-token
```

#### Environment Variable Configuration

You can also set the custom header using environment variables:

```ruby
# In your environment:
# MCP_AUTH_HEADER=X-API-Key
# MCP_AUTH_TOKEN=your-secret-token

FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :token
    # Will use ENV['MCP_AUTH_HEADER'] and ENV['MCP_AUTH_TOKEN']
  }
)
```

#### With Proc-based Authentication

When using proc-based authentication, remember to access the correct header in your custom logic:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :proc,
    auth_proc: ->(request) {
      # Access X-API-Key header
      api_key = request.get_header('HTTP_X_API_KEY')
      # Validate the API key
      valid_keys = ['key1', 'key2', 'key3']
      valid_keys.include?(api_key)
    }
  }
)
```

#### 2. Proc-based Authentication

For more complex authentication scenarios, you can use a proc that receives the entire request object:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :proc,
    auth_proc: ->(request) {
      # Your custom authentication logic here
      # Access the full request object for context
      token = request.get_header('HTTP_AUTHORIZATION')&.gsub(/^Bearer\s+/i, '')
      User.find_by(api_token: token).present?
    }
  }
)
```

This allows you to:
- Check tokens against your database
- Implement expiring tokens
- Validate user permissions
- Access request parameters for context-specific authentication
- Implement custom header or cookie-based authentication

#### 3. HTTP Basic Authentication

For applications that prefer username/password authentication:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :http_basic,
    auth_user: 'admin',  # Username to accept
    auth_password: 'secret'  # Password to accept
  }
)
```

You can also set these values using environment variables:
```ruby
# Set MCP_AUTH_USER and MCP_AUTH_PASSWORD in your environment
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :http_basic
    # Will use ENV['MCP_AUTH_USER'] and ENV['MCP_AUTH_PASSWORD']
  }
)
```

### Authentication Exemptions

Some paths can be exempted from authentication:

```ruby
FastMcp.authenticated_rack_middleware(app,
  authenticate: true,
  auth_options: {
    auth_strategy: :token,
    auth_token: 'your-secret-token',
    auth_exempt_paths: ['/health-check', '/mcp/public']  # Paths that don't require authentication
  }
)
```

### Authentication Environment Variables

For security best practices, you can use environment variables for sensitive authentication information:

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `MCP_AUTH_TOKEN` | The token for token-based authentication | None (Required) |
| `MCP_AUTH_HEADER` | The header name for token-based auth | `Authorization` |
| `MCP_AUTH_USER` | The username for HTTP Basic authentication | None (Required) |
| `MCP_AUTH_PASSWORD` | The password for HTTP Basic authentication | None (Required) |

## Best Practices

Here are some best practices to enhance the security of your MCP server:

1. **Always validate Origin headers** (enabled by default)
2. **Use authentication** for all MCP endpoints in production
3. **Deploy behind HTTPS** in production environments
4. **Keep your auth credentials in environment variables** rather than in code
5. **Implement proper error handling** to avoid leaking sensitive information
6. **Validate inputs thoroughly** in your tool implementations
7. **Implement rate limiting** for MCP endpoints to prevent abuse
8. **Follow the principle of least privilege** when implementing tools
9. **Log security events** to detect and respond to potential security incidents

## Additional Resources

- [OWASP Top Ten](https://owasp.org/www-project-top-ten/) for general web application security guidance
- [Ruby on Rails Security Guide](https://guides.rubyonrails.org/security.html) for Rails-specific security guidance
- [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) for protecting against XSS attacks
