# Security Features in Fast MCP

Security is a critical aspect of any application that exposes functionality through APIs, especially when those APIs can be called by AI models or external clients. Fast MCP provides several security features to help protect your applications.

## Table of Contents

- [DNS Rebinding Protection](#dns-rebinding-protection)
- [Authentication](#authentication)
- [HTTPS and SSL](#https-and-ssl)
- [Best Practices](#best-practices)

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

Fast MCP supports token-based authentication for all connections to ensure only authorized clients can access your MCP server.

### Basic Authentication

To enable authentication, use the `authenticated_rack_middleware` method:

```ruby
# Enable authentication
FastMcp.authenticated_rack_middleware(app,
  auth_token: 'your-secret-token',
  # other options...
)
```

### Custom Authentication Headers

You can configure the header name used for authentication:

```ruby
FastMcp.authenticated_rack_middleware(app,
  auth_token: 'your-secret-token',
  auth_header_name: 'X-API-Key',  # Default is 'Authorization'
  # other options...
)
```

### Authentication Exemptions

Some paths can be exempted from authentication:

```ruby
FastMcp.authenticated_rack_middleware(app,
  auth_token: 'your-secret-token',
  auth_exempt_paths: ['/health-check'],  # Paths that don't require authentication
  # other options...
)
```

## Best Practices

Here are some best practices to enhance the security of your MCP server:

1. **Always validate Origin headers** (enabled by default)
2. **Use authentication** for all MCP endpoints in production
3. **Deploy behind HTTPS** in production environments
4. **Keep your auth_token secret** and rotate it regularly
5. **Implement proper error handling** to avoid leaking sensitive information
6. **Validate inputs thoroughly** in your tool implementations
7. **Implement rate limiting** for MCP endpoints to prevent abuse
8. **Follow the principle of least privilege** when implementing tools
9. **Log security events** to detect and respond to potential security incidents

## Additional Resources

- [OWASP Top Ten](https://owasp.org/www-project-top-ten/) for general web application security guidance
- [Ruby on Rails Security Guide](https://guides.rubyonrails.org/security.html) for Rails-specific security guidance
- [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) for protecting against XSS attacks
