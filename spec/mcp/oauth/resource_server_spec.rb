# frozen_string_literal: true

RSpec.describe FastMcp::OAuth::ResourceServer do
  let(:logger) { Logger.new(nil) }
  let(:token_validator) { instance_double(FastMcp::OAuth::TokenValidator) }
  let(:resource_server) { described_class.new(logger: logger) }

  before do
    allow(FastMcp::OAuth::TokenValidator).to receive(:new).and_return(token_validator)
  end

  describe '#initialize' do
    it 'initializes with default scopes' do
      expect(resource_server.scope_definitions).to include(
        'mcp:read' => 'Read access to MCP resources',
        'mcp:write' => 'Write access to MCP resources',
        'mcp:tools' => 'Access to execute MCP tools',
        'mcp:admin' => 'Administrative access to MCP server'
      )
    end

    it 'accepts custom scopes' do
      custom_server = described_class.new(
        custom_scopes: { 'custom:scope' => 'Custom scope description' }
      )
      
      expect(custom_server.scope_definitions).to include('custom:scope' => 'Custom scope description')
    end
  end

  describe '#authorize_request' do
    let(:mock_request) do
      double('request',
             get_header: nil)
    end

    context 'with missing token' do
      it 'raises UnauthorizedError when no token is present' do
        allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return(nil)
        
        expect { resource_server.authorize_request(mock_request) }
          .to raise_error(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Missing authentication token')
      end
    end

    context 'with valid token' do
      let(:valid_token) { 'Bearer valid_jwt_token' }

      before do
        allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return(valid_token)
        allow(mock_request).to receive(:get_header).with('HTTP_X_FORWARDED_PROTO').and_return('https')
        allow(token_validator).to receive(:validate_token).and_return(true)
        allow(token_validator).to receive(:extract_claims).and_return({
          'sub' => 'user123',
          'scope' => 'mcp:read mcp:write',
          'iss' => 'https://auth.example.com',
          'aud' => 'mcp-api',
          'exp' => Time.now.to_i + 3600
        })
      end

      it 'successfully authorizes request with valid token' do
        result = resource_server.authorize_request(mock_request)
        
        expect(result).to include(
          subject: 'user123',
          scopes: ['mcp:read', 'mcp:write'],
          issuer: 'https://auth.example.com'
        )
      end

      it 'validates required scopes' do
        expect(token_validator).to receive(:validate_token)
          .with('valid_jwt_token', required_scopes: ['mcp:admin'])
          .and_return(true)

        resource_server.authorize_request(mock_request, required_scopes: ['mcp:admin'])
      end

      it 'raises UnauthorizedError for invalid token' do
        allow(token_validator).to receive(:validate_token).and_return(false)
        
        expect { resource_server.authorize_request(mock_request) }
          .to raise_error(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Invalid or expired token')
      end
    end

    context 'with HTTPS requirement' do
      let(:http_request) do
        double('request').tap do |req|
          allow(req).to receive(:get_header) do |header|
            case header
            when 'HTTP_AUTHORIZATION'
              'Bearer valid_token'
            when 'HTTP_X_FORWARDED_PROTO'
              'http'
            when 'HTTP_HOST'
              'example.com'
            when 'rack.url_scheme'
              'http'
            when 'SERVER_NAME'
              'example.com'
            end
          end
        end
      end

      it 'rejects HTTP requests when HTTPS is required' do
        server = described_class.new(require_https: true)
        
        expect { server.authorize_request(http_request) }
          .to raise_error(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'HTTPS required for OAuth requests')
      end

      it 'allows HTTP requests from localhost' do
        localhost_request = double('request').tap do |req|
          allow(req).to receive(:get_header) do |header|
            case header
            when 'HTTP_AUTHORIZATION'
              'Bearer valid_token'
            when 'HTTP_X_FORWARDED_PROTO'
              'http'
            when 'HTTP_HOST'
              'localhost:3000'
            when 'rack.url_scheme'
              'http'
            when 'SERVER_NAME'
              'localhost'
            end
          end
        end

        allow(token_validator).to receive(:validate_token).and_return(true)
        allow(token_validator).to receive(:extract_claims).and_return({ 'sub' => 'user123' })

        expect { resource_server.authorize_request(localhost_request) }.not_to raise_error
      end
    end
  end

  describe '#scope?' do
    let(:mock_request) do
      double('request').tap do |req|
        allow(req).to receive(:get_header) do |header|
          'Bearer valid_token' if header == 'HTTP_AUTHORIZATION'
        end
      end
    end

    it 'returns true when token has required scope' do
      allow(token_validator).to receive(:validate_token)
        .with('valid_token', required_scopes: ['mcp:read'])
        .and_return(true)

      expect(resource_server.scope?(mock_request, 'mcp:read')).to be(true)
    end

    it 'returns false when token lacks required scope' do
      allow(token_validator).to receive(:validate_token)
        .with('valid_token', required_scopes: ['mcp:admin'])
        .and_return(false)

      expect(resource_server.scope?(mock_request, 'mcp:admin')).to be(false)
    end

    it 'returns false when no token is present' do
      no_token_request = double('request', get_header: nil)
      expect(resource_server.scope?(no_token_request, 'mcp:read')).to be(false)
    end
  end

  describe '#oauth_error_response' do
    it 'generates invalid_token error response' do
      response = resource_server.oauth_error_response('invalid_token', 'Token has expired')
      
      expect(response[:status]).to eq(401)
      expect(response[:headers]['WWW-Authenticate']).to include('Bearer error="invalid_token"')
      expect(response[:headers]['Content-Type']).to eq('application/json')
      
      body = JSON.parse(response[:body])
      expect(body['error']['code']).to eq(-32_000)
      expect(body['error']['message']).to eq('Token has expired')
    end

    it 'generates insufficient_scope error response' do
      response = resource_server.oauth_error_response('insufficient_scope', 'Missing mcp:admin scope', 403)
      
      expect(response[:status]).to eq(403)
      expect(response[:headers]['WWW-Authenticate']).to include('Bearer error="insufficient_scope"')
      
      body = JSON.parse(response[:body])
      expect(body['error']['data']['error']).to eq('insufficient_scope')
    end
  end

  describe 'token extraction' do
    let(:mock_request) { double('request') }

    it 'extracts Bearer token' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('Bearer abc123')
      token = resource_server.send(:extract_bearer_token, mock_request)
      expect(token).to eq('abc123')
    end

    it 'extracts token without Bearer prefix' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('abc123def')
      token = resource_server.send(:extract_bearer_token, mock_request)
      expect(token).to eq('abc123def')
    end

    it 'returns nil for invalid authorization header' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('Invalid header!')
      token = resource_server.send(:extract_bearer_token, mock_request)
      expect(token).to be_nil
    end
  end

  describe 'localhost detection' do
    let(:mock_request) { double('request') }

    it 'detects localhost requests' do
      allow(mock_request).to receive(:get_header).with('HTTP_HOST').and_return('localhost:3000')
      expect(resource_server.send(:localhost_request?, mock_request)).to be(true)
    end

    it 'detects 127.0.0.1 requests' do
      allow(mock_request).to receive(:get_header).with('HTTP_HOST').and_return('127.0.0.1:8080')
      expect(resource_server.send(:localhost_request?, mock_request)).to be(true)
    end

    it 'detects IPv6 localhost requests' do
      allow(mock_request).to receive(:get_header).with('HTTP_HOST').and_return('[::1]:3000')
      expect(resource_server.send(:localhost_request?, mock_request)).to be(true)
    end

    it 'rejects non-localhost requests' do
      allow(mock_request).to receive(:get_header).with('HTTP_HOST').and_return('example.com')
      expect(resource_server.send(:localhost_request?, mock_request)).to be(false)
    end
  end
end