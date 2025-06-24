# frozen_string_literal: true

# Rails OAuth 2.1 MCP Integration Example
# 
# This example shows how to integrate OAuth 2.1 protected MCP servers
# into Rails applications with proper security configuration.
#
# Features demonstrated:
# - Environment-based configuration
# - Integration with Rails authentication systems
# - Proper middleware configuration
# - Development vs production settings
# - Error handling and logging

# config/initializers/fast_mcp.rb
# =====================================

# OAuth 2.1 MCP Server Configuration for Rails
Rails.application.configure do
  # Configure MCP server with OAuth 2.1 support
  config.after_initialize do
    # Only enable MCP in development and production (skip test environment)
    next if Rails.env.test?
    
    # Configure OAuth 2.1 MCP server
    FastMcp.mount_in_rails(
      Rails.application,
      
      # Basic Configuration
      name: Rails.application.class.module_parent_name.underscore,
      version: '1.0.0',
      logger: Rails.logger,
      transport: :oauth, # Enable OAuth 2.1 transport
      path: '/api/mcp',
      
      # OAuth 2.1 Security Configuration
      oauth_enabled: true,
      require_https: Rails.env.production?, # HTTPS required in production
      resource_identifier: "#{Rails.application.routes.url_helpers.root_url}api/mcp",
      
      # Token Validation Configuration
      **oauth_token_config,
      
      # Scope Configuration
      tools_scope: 'mcp:tools',
      resources_scope: 'mcp:resources', 
      admin_scope: 'mcp:admin',
      
      # CORS Configuration (for frontend clients)
      cors_enabled: true,
      allowed_origins: Rails.env.production? ? ENV['ALLOWED_ORIGINS']&.split(',') : ['localhost'],
      
      # Optional: Token Introspection (for microservices)
      introspection_endpoint: ENV['OAUTH_INTROSPECTION_ENDPOINT'],
      client_id: ENV['MCP_CLIENT_ID'],
      client_secret: ENV['MCP_CLIENT_SECRET']
      
    ) do |server|
      # Register your MCP tools and resources
      setup_mcp_tools(server)
      setup_mcp_resources(server)
    end
  end
end

# OAuth token validation configuration
def oauth_token_config
  if ENV['JWT_VALIDATION_ENABLED'] == 'true'
    # JWT Token Validation (recommended for production)
    {
      issuer: ENV['OAUTH_ISSUER'],
      audience: ENV['MCP_AUDIENCE'] || "#{Rails.application.routes.url_helpers.root_url}api/mcp",
      jwks_uri: ENV['OAUTH_JWKS_URI'],
      
      # Optional: HMAC secret for shared-secret JWTs
      hmac_secret: ENV['JWT_HMAC_SECRET'],
      
      # Optional: Authorization server discovery
      # issuer: ENV['OAUTH_ISSUER'], # Will auto-discover endpoints
    }
  else
    # Opaque Token Validation (for custom token systems)
    {
      opaque_token_validator: method(:validate_opaque_token)
    }
  end
end

# Custom opaque token validator
# In production, this would integrate with your authentication system
def validate_opaque_token(token)
  # Example: Integration with existing Rails authentication
  user = User.find_by(api_token: token)
  return { valid: false } unless user&.active?
  
  # Map user roles to OAuth scopes
  scopes = []
  scopes << 'mcp:resources' if user.can?(:read, :mcp_resources)
  scopes << 'mcp:tools' if user.can?(:execute, :mcp_tools)
  scopes << 'mcp:admin' if user.admin?
  
  {
    valid: true,
    scopes: scopes,
    subject: user.id.to_s,
    client_id: 'rails_app',
    username: user.email
  }
rescue StandardError => e
  Rails.logger.error "Token validation error: #{e.message}"
  { valid: false }
end

# MCP Tools Registration
def setup_mcp_tools(server)
  # Example: User Management Tool (requires admin scope)
  server.register_tool(UserManagementTool) if defined?(UserManagementTool)
  
  # Example: Database Query Tool (requires tools scope)
  server.register_tool(DatabaseQueryTool) if defined?(DatabaseQueryTool)
  
  # Example: File Management Tool (requires tools scope)
  server.register_tool(FileManagementTool) if defined?(FileManagementTool)
end

# MCP Resources Registration  
def setup_mcp_resources(server)
  # Example: User Resource (requires read scope)
  server.register_resource(UserResource) if defined?(UserResource)
  
  # Example: Application Logs Resource (requires admin scope)
  server.register_resource(LogsResource) if defined?(LogsResource)
  
  # Example: Configuration Resource (requires read scope)
  server.register_resource(ConfigResource) if defined?(ConfigResource)
end

# Example MCP Tool Implementation
# ================================

class UserManagementTool < FastMcp::Tool
  tool_name 'manage_users'
  description 'Manage application users (requires admin privileges)'
  
  arguments do
    required(:action).filled(:string).description('Action: list, create, update, delete')
    optional(:user_id).filled(:integer).description('User ID for update/delete operations')
    optional(:user_data).hash.description('User data for create/update operations')
  end
  
  def call(action:, user_id: nil, user_data: {})
    # Verify admin scope from OAuth token
    verify_scope!('mcp:admin')
    
    case action
    when 'list'
      success(users: User.active.select(:id, :email, :name, :created_at))
    when 'create'
      user = User.create!(user_data)
      success(user: user.slice(:id, :email, :name))
    when 'update'
      user = User.find(user_id)
      user.update!(user_data)
      success(user: user.slice(:id, :email, :name))
    when 'delete'
      User.find(user_id).destroy!
      success(message: 'User deleted successfully')
    else
      error("Invalid action: #{action}")
    end
  rescue ActiveRecord::RecordNotFound
    error('User not found')
  rescue ActiveRecord::RecordInvalid => e
    error("Validation failed: #{e.message}")
  end
  
  private
  
  def verify_scope!(required_scope)
    # Access OAuth token info passed by the transport
    oauth_scopes = headers['oauth-scopes']&.split(' ') || []
    
    unless oauth_scopes.include?(required_scope)
      raise FastMcp::Tool::ArgumentError, "Insufficient privileges: #{required_scope} scope required"
    end
  end
end

# Example MCP Resource Implementation
# ===================================

class UserResource < FastMcp::Resource
  resource_name 'User'
  description 'Access user information (requires read privileges)'
  uri 'user:///{user_id}'
  
  def content(user_id:)
    # Verify read scope from OAuth token  
    verify_scope!('mcp:resources')
    
    user = User.find(user_id)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      created_at: user.created_at,
      role: user.role,
      active: user.active?
    }.to_json
  rescue ActiveRecord::RecordNotFound
    raise FastMcp::Resource::NotFoundError, 'User not found'
  end
  
  private
  
  def verify_scope!(required_scope)
    oauth_scopes = headers['oauth-scopes']&.split(' ') || []
    
    unless oauth_scopes.include?(required_scope)
      raise FastMcp::Resource::ForbiddenError, "Insufficient privileges: #{required_scope} scope required"
    end
  end
end

# Development Configuration
# =========================

# config/environments/development.rb
Rails.application.configure do
  # Enable detailed MCP logging in development
  config.log_level = :debug
  
  # Allow HTTP for local development
  config.force_ssl = false
  
  # CORS configuration for local frontend development
  config.hosts << "localhost"
  config.hosts << "127.0.0.1"
end

# Production Configuration
# ========================

# config/environments/production.rb  
Rails.application.configure do
  # Security settings for production
  config.force_ssl = true
  config.ssl_options = { 
    redirect: { exclude: ->(request) { request.path.start_with?('/health') } }
  }
  
  # Strict CORS policy
  config.hosts << ENV['DOMAIN']
end

# Environment Variables (.env)
# ============================

# Required OAuth Configuration
# OAUTH_ISSUER=https://your-auth-server.com
# OAUTH_JWKS_URI=https://your-auth-server.com/.well-known/jwks.json
# MCP_AUDIENCE=https://your-app.com/api/mcp

# Optional Configuration  
# JWT_VALIDATION_ENABLED=true
# JWT_HMAC_SECRET=your-secret-key
# OAUTH_INTROSPECTION_ENDPOINT=https://your-auth-server.com/oauth/introspect
# MCP_CLIENT_ID=your-mcp-client-id
# MCP_CLIENT_SECRET=your-client-secret
# ALLOWED_ORIGINS=https://your-frontend.com,https://another-domain.com

# Docker Configuration
# ====================

# Dockerfile
FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache \
  build-base \
  postgresql-dev \
  nodejs \
  npm

WORKDIR /app

# Copy Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application
COPY . .

# Expose MCP port
EXPOSE 3000

# Health check for MCP endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["rails", "server", "-b", "0.0.0.0"]

# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - RAILS_ENV=production
      - OAUTH_ISSUER=https://your-auth-server.com
      - OAUTH_JWKS_URI=https://your-auth-server.com/.well-known/jwks.json
      - MCP_AUDIENCE=https://your-app.com/api/mcp
      - DATABASE_URL=postgresql://user:pass@db:5432/myapp
    depends_on:
      - db
      
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=mypassword
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:

# Testing Configuration
# =====================

# spec/support/oauth_helpers.rb
module OAuthHelpers
  def generate_test_jwt(scopes: ['mcp:resources'], subject: 'test_user')
    payload = {
      sub: subject,
      scope: scopes.join(' '),
      iss: 'test-issuer',
      aud: 'test-audience',
      exp: 1.hour.from_now.to_i,
      iat: Time.now.to_i
    }
    
    JWT.encode(payload, 'test-secret', 'HS256')
  end
  
  def oauth_headers(token)
    {
      'Authorization' => "Bearer #{token}",
      'MCP-Protocol-Version' => '2025-06-18'
    }
  end
end

# spec/requests/mcp_api_spec.rb
RSpec.describe 'MCP API', type: :request do
  include OAuthHelpers
  
  describe 'GET /api/mcp' do
    context 'with valid token' do
      it 'allows access to resources' do
        token = generate_test_jwt(scopes: ['mcp:resources'])
        
        post '/api/mcp', 
          params: { jsonrpc: '2.0', method: 'resources/list', id: 1 }.to_json,
          headers: oauth_headers(token).merge('Content-Type' => 'application/json')
          
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['result']).to be_present
      end
    end
    
    context 'with insufficient scope' do
      it 'returns forbidden error' do
        token = generate_test_jwt(scopes: ['mcp:tools']) # Wrong scope
        
        post '/api/mcp',
          params: { jsonrpc: '2.0', method: 'resources/list', id: 1 }.to_json,
          headers: oauth_headers(token).merge('Content-Type' => 'application/json')
          
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('insufficient_scope')
      end
    end
  end
end

# Monitoring and Observability
# ============================

# config/initializers/mcp_monitoring.rb
if Rails.env.production?
  # Add custom metrics for MCP usage
  ActiveSupport::Notifications.subscribe('mcp.request') do |name, start, finish, id, payload|
    duration = finish - start
    
    # Log MCP metrics
    Rails.logger.info({
      event: 'mcp_request',
      method: payload[:method],
      duration_ms: (duration * 1000).round(2),
      oauth_subject: payload[:oauth_subject],
      oauth_scopes: payload[:oauth_scopes],
      success: payload[:success]
    }.to_json)
    
    # Send to monitoring system (DataDog, New Relic, etc.)
    # StatsD.increment('mcp.requests', tags: ["method:#{payload[:method]}"])
    # StatsD.histogram('mcp.duration', duration * 1000, tags: ["method:#{payload[:method]}"])
  end
end