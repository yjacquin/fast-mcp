# Rails Integration Guide

Fast MCP provides seamless integration with Ruby on Rails through Rails-specific aliases and a convenient mounting helper.

## Quick Start

### 1. Installation

Add to your Gemfile:

```ruby
gem 'fast-mcp'
```

Run the installer:

```bash
bundle install
rails generate fast_mcp:install
```

This creates `config/initializers/fast_mcp.rb` with a sample configuration.

### 2. Rails-Specific Aliases

Fast MCP provides Rails-friendly class names that feel natural in a Rails app:

```ruby
# Use ActionTool::Base instead of FastMcp::Tool
class CreateUserTool < ActionTool::Base
  description "Create a user"

  arguments do
    required(:name).filled(:string).description("User's name")
    required(:email).filled(:string).description("User's email")
  end

  def call(name:, email:)
    User.create!(name: name, email: email)
  end
end

# Use ActionResource::Base instead of FastMcp::Resource
class UsersResource < ActionResource::Base
  uri "myapp:///users"
  resource_name "Users List"
  mime_type "application/json"

  def content
    User.all.to_json
  end
end
```

### 3. Mounting in Rails

Use `FastMcp.mount_in_rails` to automatically mount the MCP server:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.mount_in_rails(
  Rails.application,
  name: 'My Rails App',
  version: '1.0.0',
  path: '/mcp'  # Single unified endpoint
) do |server|
  Rails.application.config.after_initialize do
    # Auto-register all tool and resource classes
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end
```

This mounts the MCP server at `/mcp` using the modern StreamableHTTP transport.

## Transport Options

### Basic StreamableHTTP (Default)

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  name: 'My App',
  version: '1.0.0',
  path: '/mcp'
) do |server|
  # Register tools and resources
end
```

### With Token Authentication

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  transport: :authenticated,
  name: 'My App',
  version: '1.0.0',
  path: '/mcp',
  auth_token: Rails.application.credentials.mcp_token
) do |server|
  # Register tools and resources
end
```

### With OAuth 2.1

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  transport: :oauth,
  name: 'My App',
  version: '1.0.0',
  path: '/mcp',
  oauth_enabled: true,
  jwt_enabled: true,
  jwt_jwks_url: 'https://auth.example.com/.well-known/jwks.json',
  resource_identifier: 'https://api.example.com',
  require_https: Rails.env.production?
) do |server|
  # Register tools and resources
end
```

See [OAuth Configuration Guide](./oauth-configuration-guide.md) for detailed OAuth setup.

## Dynamic Filtering

Control which tools and resources are available based on request context:

```ruby
FastMcp.mount_in_rails(
  Rails.application,
  name: 'My App',
  version: '1.0.0'
) do |server|
  # Filter tools based on authentication
  server.on_filter_tools do |tools, context|
    user = context[:current_user]

    if user&.admin?
      tools
    else
      tools.reject { |tool| tool.tags.include?('admin') }
    end
  end

  # Filter resources based on permissions
  server.on_filter_resources do |resources, context|
    user = context[:current_user]
    resources.select { |resource| user.can_access?(resource) }
  end

  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
  end
end
```

## Organizing Tools and Resources

### Base Classes

Create base classes for common functionality:

```ruby
# app/mcp/application_tool.rb
class ApplicationTool < ActionTool::Base
  # Shared tool logic

  def current_user
    # Access user from context if needed
  end
end

# app/mcp/application_resource.rb
class ApplicationResource < ActionResource::Base
  # Shared resource logic
end
```

### Directory Structure

Organize your MCP classes:

```
app/
  mcp/
    tools/
      create_user_tool.rb
      update_user_tool.rb
      delete_user_tool.rb
    resources/
      users_resource.rb
      posts_resource.rb
    application_tool.rb
    application_resource.rb
```

### Autoloading

Add to your `config/application.rb`:

```ruby
config.autoload_paths += %W[#{config.root}/app/mcp]
```

## Testing

### RSpec Example

```ruby
# spec/mcp/tools/create_user_tool_spec.rb
RSpec.describe CreateUserTool do
  describe '#call' do
    it 'creates a user' do
      result = described_class.new.call(
        name: 'John Doe',
        email: 'john@example.com'
      )

      expect(result).to be_a(User)
      expect(result.name).to eq('John Doe')
      expect(result.email).to eq('john@example.com')
    end
  end
end
```

## Migration from Legacy Transport

If you're upgrading from an older version using legacy transports, see the [Rails Migration Guide](./rails_migration_guide.md) for detailed migration instructions.

## Additional Resources

- [OAuth Configuration Guide](./oauth-configuration-guide.md)
- [Security Configuration](./security_configuration.md)
- [StreamableHTTP Transport](./streamable_http_transport.md)
- [Rails Demo App](../examples/rails-demo-app/)

## Common Patterns

### Request Context

Access request information in your tools:

```ruby
class MyTool < ActionTool::Base
  def call(**args)
    # Access request context
    headers = context[:headers]
    user = context[:current_user]

    # Your logic here
  end
end
```

### Error Handling

```ruby
class CreateUserTool < ActionTool::Base
  def call(name:, email:)
    user = User.create!(name: name, email: email)
    { success: true, user: user }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  end
end
```

### Background Jobs

```ruby
class ProcessDataTool < ActionTool::Base
  description "Process data in background"

  def call(data_id:)
    DataProcessingJob.perform_later(data_id)
    { status: 'queued', message: 'Processing started' }
  end
end
```

## Performance Considerations

### Use Fiber-Based Servers

For best performance with concurrent connections, use Falcon (fiber-based server):

```ruby
# Gemfile
gem 'falcon'

# Run with:
falcon serve -b http://localhost:3000
```

Fast MCP automatically detects the fiber scheduler and uses async mode.

### Caching

Cache expensive resource computations:

```ruby
class ExpensiveResource < ActionResource::Base
  def content
    Rails.cache.fetch("expensive_resource", expires_in: 5.minutes) do
      # Expensive computation
      compute_expensive_data.to_json
    end
  end
end
```

## Security Best Practices

1. **Use Authentication**: Always use authenticated or OAuth transports in production
2. **Validate Input**: Tool arguments are automatically validated via Dry-Schema
3. **Filter Sensitive Tools**: Use dynamic filtering to restrict access to sensitive operations
4. **Use HTTPS**: Enable `require_https: true` in production for OAuth
5. **Limit Scope**: Only register tools and resources that are actually needed

## Troubleshooting

### Server Not Responding

Check your routes:

```bash
rails routes | grep mcp
```

You should see routes for your MCP endpoint.

### Tools Not Found

Ensure your tools are autoloaded and registered:

```ruby
# In rails console
FastMcp::Server.instance.list_tools
```

### OAuth Issues

See the [OAuth Troubleshooting Guide](./oauth-troubleshooting.md) for detailed debugging steps.
