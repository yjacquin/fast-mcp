# Dynamic Tool and Resource Filtering

Fast MCP provides a powerful filtering system that allows you to dynamically control which tools and resources are available based on request context. This is useful for implementing:

- Permission-based access control
- API versioning
- Feature flags
- Multi-tenancy
- Environment-specific functionality
- Rate limiting

## Table of Contents

- [Overview](#overview)
- [Basic Usage](#basic-usage)
- [Tool Tagging](#tool-tagging)
- [Filter Functions](#filter-functions)
- [Advanced Usage](#advanced-usage)
- [Thread Safety](#thread-safety)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Overview

The filtering system works by:

1. Defining filters on the server that examine request context
2. Creating request-scoped server instances with filtered tools/resources
3. Using these filtered servers to handle specific requests

This approach is completely thread-safe as each request gets its own server instance with the appropriate tools and resources.

## Basic Usage

### Adding a Simple Filter

```ruby
FastMcp.mount_in_rails(app) do |server|
  # Register all tools
  server.register_tools(AdminTool, UserTool, PublicTool)

  # Add a filter based on request parameters
  server.filter_tools do |request, tools|
    role = request.params['role']

    case role
    when 'admin'
      tools # Admin sees all tools
    when 'user'
      tools.reject { |t| t.tags.include?(:admin) }
    else
      tools.select { |t| t.tags.include?(:public) }
    end
  end
end
```

### Filtering Resources

```ruby
server.filter_resources do |request, resources|
  tenant_id = request.headers['X-Tenant-ID']

  # Only show resources for the current tenant
  resources.select { |r| r.tenant_id == tenant_id }
end
```

## Tool Tagging

Tools can be tagged for easier filtering:

```ruby
class DangerousTool < FastMcp::Tool
  tool_name 'delete_all'
  description 'Delete all data'
  tags :admin, :dangerous, :write

  def call
    # Dangerous operation
  end
end

class ReadOnlyTool < FastMcp::Tool
  tool_name 'list_users'
  description 'List all users'
  tags :read, :safe

  def call
    # Safe read operation
  end
end
```

Tools can also have metadata:

```ruby
class ReportingTool < FastMcp::Tool
  tool_name 'generate_report'
  description 'Generate a report'

  metadata :category, 'reporting'
  metadata :cpu_intensive, true
  metadata :requires_license, 'enterprise'

  def call
    # Generate report
  end
end
```

## Filter Functions

Filter functions receive two parameters:
- `request`: A Rack::Request object with access to params, headers, etc.
- `tools` or `resources`: An array of available tools/resources

They should return a filtered array.

### Multiple Filters

Filters are applied in sequence:

```ruby
# First filter: Remove dangerous tools in production
server.filter_tools do |request, tools|
  if Rails.env.production?
    tools.reject { |t| t.tags.include?(:dangerous) }
  else
    tools
  end
end

# Second filter: Apply role-based access
server.filter_tools do |request, tools|
  role = request.params['role']
  role == 'admin' ? tools : tools.reject { |t| t.tags.include?(:admin) }
end
```

### Header-Based Filtering

```ruby
server.filter_tools do |request, tools|
  api_version = request.env['HTTP_X_API_VERSION']

  case api_version
  when 'v2'
    tools # All tools available in v2
  when 'v1'
    tools.reject { |t| t.tags.include?(:v2_only) }
  else
    [] # No tools for unversioned requests
  end
end
```

## Advanced Usage

### Custom Server in Environment

For advanced use cases, you can provide a custom server instance via the environment:

```ruby
# In a middleware or controller
env['fast_mcp.server'] = custom_filtered_server
```

This takes precedence over any configured filters.

### Caching

The RackTransport automatically caches filtered server instances based on request parameters to improve performance. Identical requests will reuse the same filtered server instance.

### Combining with Authentication

```ruby
server.filter_tools do |request, tools|
  # Get user from your authentication system
  user = authenticate_request(request)

  return [] unless user # No tools for unauthenticated requests

  # Filter based on user permissions
  tools.select { |t| user.can_access_tool?(t) }
end
```

## Thread Safety

The filtering system is designed to be completely thread-safe:

- Each request gets its own server instance
- No shared state is modified
- Original server configuration remains unchanged
- Concurrent requests with different filters work correctly

## Examples

### Permission-Based Access Control

```ruby
class AdminTool < FastMcp::Tool
  tags :admin
  description "Administrative functions"

  def call
    "Admin action performed"
  end
end

class UserTool < FastMcp::Tool
  tags :user
  description "User functions"

  def call
    "User action performed"
  end
end

server.filter_tools do |request, tools|
  user_role = request.headers['X-User-Role']

  case user_role
  when 'admin'
    tools
  when 'user'
    tools.reject { |t| t.tags.include?(:admin) }
  else
    []
  end
end
```

### Feature Flags

```ruby
server.filter_tools do |request, tools|
  user_id = request.headers['X-User-ID']
  enabled_features = FeatureFlags.for_user(user_id)

  tools.reject do |tool|
    tool.metadata(:feature_flag) &&
    !enabled_features.include?(tool.metadata(:feature_flag))
  end
end
```

### Rate Limiting

```ruby
server.filter_tools do |request, tools|
  client_ip = request.ip

  if RateLimiter.exceeded?(client_ip, :expensive_operations)
    tools.reject { |t| t.metadata(:expensive) }
  else
    tools
  end
end
```

## Best Practices

1. **Keep Filters Fast**: Filters run on every request, so keep them efficient
2. **Use Tags Wisely**: Create a consistent tagging system across your tools
3. **Cache When Possible**: The built-in caching helps, but consider caching expensive checks
4. **Fail Secure**: When in doubt, exclude tools rather than include them
5. **Log Filter Actions**: Consider logging when tools are filtered for debugging
6. **Test Thoroughly**: Write tests for your filter logic to ensure security

## Migration from Custom Solutions

If you have existing middleware that modifies tool availability, you can migrate to the filtering system:

```ruby
# Before: Custom middleware
class ToolFilterMiddleware
  def call(env)
    # Complex logic to modify server tools
  end
end

# After: Using filter_tools
server.filter_tools do |request, tools|
  # Same logic, but cleaner and thread-safe
end
```

The filtering system handles all the complexity of creating request-scoped servers and ensuring thread safety.
