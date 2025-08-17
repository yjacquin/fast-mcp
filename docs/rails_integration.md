# Rails Integration Guide

Fast MCP provides seamless integration with Ruby on Rails applications, including automatic discovery of tools, resources, and prompts. This guide walks you through setting up and using Fast MCP in a Rails application.

## Installation

Add the Fast MCP gem to your Rails application's Gemfile:

```ruby
gem 'fast-mcp'
```

Then run:

```bash
bundle install
```

## Generator Setup

Fast MCP includes a Rails generator that sets up the basic structure for your MCP integration:

```bash
bin/rails generate fast_mcp:install
```

This generator creates:

- `app/tools/` directory for MCP tools
- `app/resources/` directory for MCP resources  
- `app/prompts/` directory for MCP prompts
- `app/tools/application_tool.rb` base class
- `app/resources/application_resource.rb` base class
- `app/prompts/application_prompt.rb` base class
- Basic configuration in `config/initializers/fast_mcp.rb`

## Configuration

After running the generator, configure Fast MCP in `config/initializers/fast_mcp.rb`:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.configure do |config|
  config.server_name = 'my-rails-app'
  config.server_version = '1.0.0'
  
  # Configure transport options
  config.transport = :rack  # or :stdio
  config.allowed_origins = ['http://localhost:3000']
  
  # Enable authentication if needed
  config.authentication_token = ENV['MCP_AUTH_TOKEN']
end
```

## Creating Tools

Create tools in the `app/tools/` directory. They automatically inherit from `ApplicationTool`:

```ruby
# app/tools/user_search_tool.rb
class UserSearchTool < ApplicationTool
  description "Search for users in the database"
  
  arguments do
    required(:query).filled(:string).description("Search query")
    optional(:limit).filled(:integer).description("Maximum number of results")
  end
  
  def call(query:, limit: 10)
    users = User.where("name ILIKE ?", "%#{query}%").limit(limit)
    users.map { |user| { id: user.id, name: user.name, email: user.email } }
  end
end
```

Tools have access to all Rails helpers and can interact with your models directly.

## Creating Resources

Create resources in the `app/resources/` directory:

```ruby
# app/resources/user_stats_resource.rb
class UserStatsResource < ApplicationResource
  uri "stats/users"
  resource_name "User Statistics"
  description "Current user statistics"
  mime_type "application/json"
  
  def content
    {
      total_users: User.count,
      active_users: User.where(active: true).count,
      new_users_today: User.where(created_at: Date.current.all_day).count
    }.to_json
  end
end
```

## Creating Prompts

Create prompts in the `app/prompts/` directory:

```ruby
# app/prompts/user_analysis_prompt.rb
class UserAnalysisPrompt < ApplicationPrompt
  prompt_name 'user_analysis'
  description 'Analyze user behavior patterns'
  
  arguments do
    required(:user_id).filled(:integer).description("User ID to analyze")
    optional(:timeframe).filled(:string).description("Analysis timeframe (week, month, year)")
  end
  
  def call(user_id:, timeframe: 'month')
    user = User.find(user_id)
    
    # Get user activity data
    activities = case timeframe
                 when 'week'
                   user.activities.where(created_at: 1.week.ago..Time.current)
                 when 'year'
                   user.activities.where(created_at: 1.year.ago..Time.current)
                 else # month
                   user.activities.where(created_at: 1.month.ago..Time.current)
                 end
    
    activity_summary = activities.group(:activity_type).count
    
    messages(
      assistant: "I'll analyze the user behavior for #{user.name} over the past #{timeframe}.",
      user: "User: #{user.name} (ID: #{user.id})\nActivity Summary:\n#{activity_summary.map { |type, count| "#{type}: #{count}" }.join('\n')}\n\nPlease provide insights about this user's behavior patterns."
    )
  end
end
```

## Automatic Registration

Rails integration automatically discovers and registers your tools, resources, and prompts:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.configure do |config|
  # ... other configuration ...
end

# Automatic registration happens via the Railtie
# All descendants of ApplicationTool, ApplicationResource, and ApplicationPrompt
# are automatically registered with the server
```

## Manual Registration

If you need more control over registration:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.configure do |config|
  config.auto_register = false  # Disable automatic registration
end

# Then manually register in your initializer
FastMcp.server.tap do |server|
  server.register_tool(UserSearchTool)
  server.register_resource(UserStatsResource)
  server.register_prompt(UserAnalysisPrompt)
end
```

## Mounting the MCP Server

### Option 1: Rack Middleware (Recommended)

Mount the MCP server as Rack middleware in `config/application.rb`:

```ruby
# config/application.rb
class Application < Rails::Application
  # ... other configuration ...
  
  config.middleware.use FastMcp::RackMiddleware, {
    name: 'my-rails-app',
    version: '1.0.0'
  }
end
```

### Option 2: Routes-based Mounting

Mount MCP endpoints in your routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount FastMcp::Engine => '/mcp'
  # ... your other routes ...
end
```

## Authentication Integration

Integrate with Rails authentication systems:

```ruby
# app/tools/authenticated_tool.rb
class AuthenticatedTool < ApplicationTool
  authorize do |**args|
    # Access headers for authentication
    token = headers['Authorization']&.sub(/^Bearer /, '')
    
    # Validate token using your authentication system
    user = User.find_by(api_token: token)
    user&.active?
  end
  
  private
  
  def current_user
    @current_user ||= begin
      token = headers['Authorization']&.sub(/^Bearer /, '')
      User.find_by(api_token: token)
    end
  end
end
```

Use this as a base class for tools that require authentication:

```ruby
# app/tools/secure_user_tool.rb
class SecureUserTool < AuthenticatedTool
  description "Get current user information"
  
  def call
    {
      id: current_user.id,
      name: current_user.name,
      role: current_user.role
    }
  end
end
```

## Filtering and Authorization

Implement filtering for prompts and tools:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.configure do |config|
  # ... other configuration ...
end

FastMcp.server.tap do |server|
  # Filter tools based on user permissions
  server.filter_tools do |request, tools|
    user = authenticate_user(request.headers['Authorization'])
    tools.select { |tool| tool.authorized?(user: user) }
  end
  
  # Filter prompts based on user role
  server.filter_prompts do |request, prompts|
    user = authenticate_user(request.headers['Authorization'])
    return prompts if user&.admin?
    
    prompts.reject { |prompt| prompt.tags.include?(:admin_only) }
  end
end

def authenticate_user(auth_header)
  return nil unless auth_header
  
  token = auth_header.sub(/^Bearer /, '')
  User.find_by(api_token: token)
end
```

## Working with ActiveRecord

Tools and resources can interact with ActiveRecord models:

```ruby
# app/tools/user_management_tool.rb
class UserManagementTool < ApplicationTool
  description "Manage user accounts"
  
  arguments do
    required(:action).filled(:string).description("Action to perform: create, update, delete")
    required(:user_data).hash.description("User data")
  end
  
  def call(action:, user_data:)
    case action
    when 'create'
      user = User.create!(user_data)
      { success: true, user_id: user.id }
    when 'update'
      user = User.find(user_data[:id])
      user.update!(user_data.except(:id))
      { success: true, user_id: user.id }
    when 'delete'
      User.find(user_data[:id]).destroy!
      { success: true }
    else
      raise "Unknown action: #{action}"
    end
  rescue ActiveRecord::RecordInvalid => e
    { success: false, errors: e.record.errors.full_messages }
  end
end
```

## Testing

Test your MCP components using RSpec:

```ruby
# spec/tools/user_search_tool_spec.rb
RSpec.describe UserSearchTool do
  let(:tool) { described_class.new }
  
  before do
    create(:user, name: "John Doe")
    create(:user, name: "Jane Smith")
  end
  
  it "searches users by name" do
    result = tool.call(query: "John")
    expect(result).to have(1).items
    expect(result.first[:name]).to eq("John Doe")
  end
end
```

```ruby
# spec/prompts/user_analysis_prompt_spec.rb
RSpec.describe UserAnalysisPrompt do
  let(:prompt) { described_class.new }
  let(:user) { create(:user, name: "Test User") }
  
  it "creates analysis messages" do
    result = prompt.call(user_id: user.id)
    expect(result).to be_an(Array)
    expect(result.first[:role]).to eq("assistant")
    expect(result.last[:content][:text]).to include("Test User")
  end
end
```

## Development and Debugging

Enable detailed logging in development:

```ruby
# config/environments/development.rb
Rails.application.configure do
  # ... other configuration ...
  
  config.after_initialize do
    FastMcp.logger.level = Logger::DEBUG
  end
end
```

Use the MCP Inspector to test your server:

```bash
# Test your Rails MCP server
npx @modelcontextprotocol/inspector http://localhost:3000/mcp
```

## Production Considerations

### Performance

- Use background jobs for long-running tool operations
- Cache resource content when appropriate
- Consider using read replicas for read-heavy resources

### Security

- Always validate and sanitize inputs
- Use Rails parameter filtering for sensitive data
- Implement proper authorization checks
- Use HTTPS in production

### Monitoring

Monitor MCP usage and performance:

```ruby
# config/initializers/fast_mcp.rb
FastMcp.configure do |config|
  config.before_tool_call = ->(tool_name, args) {
    Rails.logger.info "MCP Tool called: #{tool_name} with #{args.keys}"
  }
  
  config.after_tool_call = ->(tool_name, result, duration) {
    Rails.logger.info "MCP Tool completed: #{tool_name} in #{duration}ms"
  }
end
```

## Example Application

Check out the complete example Rails application in the [examples directory](../examples/rails-demo-app/) for a working implementation of all these concepts.

## Troubleshooting

### Common Issues

**Issue**: Tools not being auto-registered
- **Solution**: Ensure your tool classes inherit from `ApplicationTool` and are in the `app/tools/` directory

**Issue**: Routes conflicts
- **Solution**: Mount MCP endpoints on a specific path like `/mcp`

**Issue**: Authentication not working
- **Solution**: Verify headers are being passed correctly and your authentication logic is sound

**Issue**: Resources showing stale data
- **Solution**: Ensure you're calling `notify_resource_updated` after data changes

For more help, see the [main documentation](./integration_guide.md) or check the [examples](../examples/).