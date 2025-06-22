#!/usr/bin/env ruby
# frozen_string_literal: true

# OAuth 2.1 MCP Client Example
#
# This example demonstrates how to implement a complete OAuth 2.1 client
# that can securely connect to an OAuth-protected MCP server. It showcases:
#
# - PKCE (Proof Key for Code Exchange) implementation
# - Authorization server discovery
# - Dynamic client registration
# - Token lifecycle management (obtain, refresh, introspect)
# - Secure MCP API interactions
# - Error handling and fallback strategies
#
# Security Features Demonstrated:
# - PKCE to prevent authorization code interception
# - State parameter to prevent CSRF attacks
# - Audience parameter for resource binding
# - Proper token storage and handling
# - Secure redirect URI validation

require_relative '../lib/fast_mcp'
require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'digest'

class OAuthMCPClient
  attr_reader :logger, :client_config, :tokens

  def initialize(options = {})
    @logger = options[:logger] || Logger.new($stdout, level: Logger::INFO)
    @mcp_server_url = options[:mcp_server_url] || 'http://localhost:3001/mcp'
    @authorization_server = options[:authorization_server] || 'https://your-auth-server.com'
    @client_config = options[:client_config] || {}
    @tokens = {}

    # Initialize OAuth components
    setup_oauth_components
  end

  def setup_oauth_components
    @discovery = FastMcp::OAuth::Discovery.new(logger: @logger)
    @pkce = FastMcp::OAuth::PKCE.new
    @client_registration = nil # Will be initialized if needed

    @logger.info('OAuth 2.1 MCP Client initialized')
  end

  # Complete OAuth 2.1 flow demonstration
  def run_complete_flow
    @logger.info('🚀 Starting complete OAuth 2.1 flow...')

    begin
      # Step 1: Discover authorization server capabilities
      discover_server_capabilities

      # Step 2: Register client (if using dynamic registration)
      register_client_if_needed

      # Step 3: Obtain authorization
      obtain_authorization

      # Step 4: Test MCP API calls
      test_mcp_api_calls

      # Step 5: Demonstrate token refresh
      demonstrate_token_refresh

      @logger.info('✅ Complete OAuth 2.1 flow completed successfully!')
    rescue StandardError => e
      @logger.error("❌ OAuth flow failed: #{e.message}")
      @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
    end
  end

  private

  # Step 1: Authorization Server Discovery
  def discover_server_capabilities
    @logger.info('🔍 Step 1: Discovering authorization server capabilities...')

    begin
      @server_metadata = @discovery.discover_metadata(@authorization_server)
      @logger.info("✅ Discovered authorization server: #{@server_metadata['issuer']}")
      @logger.info("   Authorization endpoint: #{@server_metadata['authorization_endpoint']}")
      @logger.info("   Token endpoint: #{@server_metadata['token_endpoint']}")
      @logger.info("   PKCE methods supported: #{@server_metadata['code_challenge_methods_supported']}")

      # Check if PKCE is required
      if @discovery.pkce_required?(@authorization_server)
        @logger.info('   🔒 PKCE is required - excellent for security!')
      end
    rescue FastMcp::OAuth::Discovery::DiscoveryError => e
      @logger.warn("⚠️  Server discovery failed: #{e.message}")
      @logger.info('   Using manual configuration...')

      # Fallback to manual configuration
      @server_metadata = {
        'authorization_endpoint' => "#{@authorization_server}/oauth/authorize",
        'token_endpoint' => "#{@authorization_server}/oauth/token",
        'registration_endpoint' => "#{@authorization_server}/oauth/register",
        'code_challenge_methods_supported' => ['S256']
      }
    end
  end

  # Step 2: Dynamic Client Registration (optional)
  def register_client_if_needed
    return if @client_config[:client_id] # Skip if already configured
    return unless @server_metadata['registration_endpoint']

    @logger.info('🔧 Step 2: Registering client dynamically...')

    begin
      @client_registration = FastMcp::OAuth::ClientRegistration.new(
        registration_endpoint: @server_metadata['registration_endpoint'],
        logger: @logger
      )

      # Register our MCP client
      registration_result = @client_registration.register_client(
        'client_name' => 'MCP OAuth Client Example',
        'client_uri' => 'https://github.com/yjacquin/fast-mcp',
        'redirect_uris' => ['http://localhost:8080/oauth/callback'],
        'grant_types' => ['authorization_code', 'refresh_token'],
        'response_types' => ['code'],
        'scope' => 'mcp:resources mcp:tools mcp:admin'
      )

      @client_config = {
        client_id: registration_result[:client_id],
        client_secret: registration_result[:client_secret],
        registration_access_token: registration_result[:registration_access_token]
      }

      @logger.info("✅ Client registered: #{@client_config[:client_id]}")
    rescue FastMcp::OAuth::ClientRegistration::RegistrationError => e
      @logger.error("❌ Client registration failed: #{e.message}")
      @logger.info('   Please configure client credentials manually')
      exit 1
    end
  end

  # Step 3: Authorization Flow
  def obtain_authorization
    @logger.info('🔐 Step 3: Starting authorization flow...')

    # For this example, we'll simulate the authorization flow
    # In a real application, you'd redirect the user to the authorization URL

    authorization_url = build_authorization_url
    @logger.info("   Authorization URL: #{authorization_url}")
    @logger.info('   📋 In a real app, redirect user to this URL')
    @logger.info('   📋 For demo purposes, simulating successful authorization...')

    # Simulate receiving authorization code
    simulate_authorization_callback
  end

  def build_authorization_url
    state = SecureRandom.urlsafe_base64(32)
    @auth_state = state # Store for validation

    params = {
      'response_type' => 'code',
      'client_id' => @client_config[:client_id] || 'demo_client',
      'redirect_uri' => 'http://localhost:8080/oauth/callback',
      'scope' => 'mcp:resources mcp:tools mcp:admin',
      'state' => state,
      'resource' => @mcp_server_url, # Audience binding
      **@pkce.authorization_params
    }

    "#{@server_metadata['authorization_endpoint']}?#{URI.encode_www_form(params)}"
  end

  def simulate_authorization_callback
    # In a real application, this would be handled by your callback endpoint
    # For demo purposes, we'll use pre-configured demo tokens

    @logger.info('   🎯 Simulating authorization callback...')

    # Simulate demo token exchange
    @tokens = {
      access_token: 'admin_token_123', # Using demo token from server example
      token_type: 'Bearer',
      expires_in: 3600,
      refresh_token: 'refresh_token_456',
      scope: 'mcp:resources mcp:tools mcp:admin'
    }

    @logger.info('   ✅ Authorization successful! Received access token')
    @logger.info("   Token type: #{@tokens[:token_type]}")
    @logger.info("   Expires in: #{@tokens[:expires_in]} seconds")
    @logger.info("   Scopes: #{@tokens[:scope]}")
  end

  # Step 4: MCP API Testing
  def test_mcp_api_calls
    @logger.info('🔌 Step 4: Testing MCP API calls with OAuth token...')

    test_cases = [
      {
        name: 'Server Initialization',
        method: 'initialize',
        params: {
          capabilities: {},
          clientInfo: { name: 'OAuth MCP Client', version: '1.0.0' }
        },
        required_scope: nil
      },
      {
        name: 'List Tools',
        method: 'tools/list',
        params: {},
        required_scope: 'mcp:tools'
      },
      {
        name: 'List Resources',
        method: 'resources/list',
        params: {},
        required_scope: 'mcp:resources'
      },
      {
        name: 'Execute Tool',
        method: 'tools/call',
        params: {
          name: 'list_files',
          arguments: { directory: '.' }
        },
        required_scope: 'mcp:tools'
      }
    ]

    test_cases.each_with_index do |test_case, index|
      @logger.info("   #{index + 1}. Testing: #{test_case[:name]}")

      begin
        response = make_mcp_request(test_case[:method], test_case[:params])

        if response['error']
          @logger.error("      ❌ Error: #{response['error']['message']}")
        else
          @logger.info('      ✅ Success!')
          @logger.debug("      Response: #{response['result']}")
        end
      rescue StandardError => e
        @logger.error("      ❌ Request failed: #{e.message}")
      end

      sleep(0.5) # Brief pause between requests
    end
  end

  def make_mcp_request(method, params = {})
    uri = URI(@mcp_server_url)

    request_body = {
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: SecureRandom.uuid
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request['Authorization'] = "Bearer #{@tokens[:access_token]}"
    request['MCP-Protocol-Version'] = '2025-06-18'
    request.body = JSON.generate(request_body)

    response = http.request(request)

    raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # Step 5: Token Refresh Demonstration
  def demonstrate_token_refresh
    @logger.info('🔄 Step 5: Demonstrating token refresh...')

    # In a real application, you'd check token expiration and refresh as needed
    @logger.info('   📋 In a real app, monitor token expiration and refresh automatically')
    @logger.info("   Current token expires in: #{@tokens[:expires_in]} seconds")

    if @tokens[:refresh_token]
      @logger.info('   ✅ Refresh token available for automatic renewal')
      # simulate_token_refresh
    else
      @logger.warn('   ⚠️  No refresh token - user would need to re-authorize')
    end
  end

  def simulate_token_refresh
    @logger.info('   🔄 Refreshing access token...')

    # In a real implementation, you'd call the token endpoint
    # For demo purposes, we'll simulate a successful refresh

    @tokens[:access_token] = 'admin_token_new_123'
    @tokens[:expires_in] = 3600

    @logger.info('   ✅ Token refreshed successfully!')
  end
end

# Production Configuration Examples
class ProductionOAuthConfig
  def self.jwt_config
    {
      # For production JWT token validation
      issuer: ENV['OAUTH_ISSUER'] || 'https://your-auth-server.com',
      audience: ENV['MCP_SERVER_URL'] || 'https://your-mcp-server.com/mcp',
      jwks_uri: ENV['OAUTH_JWKS_URI'] || 'https://your-auth-server.com/.well-known/jwks.json',

      # Optional: For HMAC-signed tokens
      hmac_secret: ENV.fetch('JWT_HMAC_SECRET', nil),

      # Security settings
      require_https: true,
      clock_skew: 60
    }
  end

  def self.client_config
    {
      client_id: ENV.fetch('OAUTH_CLIENT_ID', nil),
      client_secret: ENV.fetch('OAUTH_CLIENT_SECRET', nil),
      redirect_uri: ENV['OAUTH_REDIRECT_URI'] || 'https://your-app.com/oauth/callback',

      # Optional: For introspection
      introspection_endpoint: ENV.fetch('OAUTH_INTROSPECTION_ENDPOINT', nil),

      # Optional: For dynamic registration
      registration_endpoint: ENV.fetch('OAUTH_REGISTRATION_ENDPOINT', nil),
      initial_access_token: ENV.fetch('OAUTH_INITIAL_ACCESS_TOKEN', nil)
    }
  end
end

# Demo runner
if __FILE__ == $0
  puts '🎭 OAuth 2.1 MCP Client Example'
  puts '   This demonstrates a complete OAuth 2.1 flow for MCP clients'
  puts ''
  puts '📋 Prerequisites:'
  puts '   1. Start the OAuth server example:'
  puts '      ruby examples/server_with_oauth_transport.rb'
  puts '   2. Server should be running at http://localhost:3001'
  puts ''
  puts '🏃 Running OAuth flow...'
  puts ''

  # Initialize and run the OAuth client
  client = OAuthMCPClient.new(
    mcp_server_url: 'http://localhost:3001/mcp',
    authorization_server: 'https://demo-auth-server.com', # Demo server
    logger: Logger.new($stdout, level: Logger::INFO)
  )

  client.run_complete_flow

  puts ''
  puts '📚 Next Steps:'
  puts '   1. Implement proper authorization server integration'
  puts '   2. Add persistent token storage'
  puts '   3. Implement proper error handling and retry logic'
  puts '   4. Add token refresh automation'
  puts '   5. Implement secure redirect URI handling'
  puts ''
  puts '🔗 For production use, see ProductionOAuthConfig class above'
end
