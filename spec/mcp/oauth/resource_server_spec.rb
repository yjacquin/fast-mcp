# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FastMcp::OAuth::ResourceServer do
  let(:logger) { Logger.new(nil) }
  let(:token_validator) { instance_double(FastMcp::OAuth::TokenValidator) }
  let(:authorization_servers) { ['https://auth.example.com'] }
  let(:resource_server) { described_class.new(authorization_servers, logger: logger) }

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
        authorization_servers,
        custom_scopes: { 'custom:scope' => 'Custom scope description' }
      )

      expect(custom_server.scope_definitions).to include('custom:scope' => 'Custom scope description')
    end
  end

  describe '#authorize_request!' do
    let(:mock_request) do
      double('request',
             get_header: nil)
    end

    context 'with missing token' do
      it 'raises InvalidRequestError when no token is present' do
        allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return(nil)

        expect { resource_server.authorize_request!(mock_request) }
          .to raise_error(FastMcp::OAuth::InvalidRequestError, 'Missing authentication token')
      end
    end

    context 'with valid token' do
      let(:valid_token) { 'Bearer valid_jwt_token' }

      before do
        allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return(valid_token)
        allow(mock_request).to receive(:get_header).with('HTTP_X_FORWARDED_PROTO').and_return('https')
        allow(mock_request).to receive(:get_header).with('rack.url_scheme').and_return('https')
      end

      it 'successfully authorizes request with valid token' do
        allow(token_validator).to receive(:validate_token).and_return(true)
        allow(token_validator).to receive(:extract_claims).and_return({ 'sub' => 'user123' })

        result = resource_server.authorize_request!(mock_request)
        expect(result).to include(subject: 'user123')
      end

      it 'validates required scopes' do
        allow(token_validator).to receive(:validate_token).with('valid_jwt_token', required_scopes: ['mcp:admin']).and_return(true)
        allow(token_validator).to receive(:validate_token).with('valid_jwt_token').and_return(true)
        allow(token_validator).to receive(:extract_claims).and_return({ 'sub' => 'user123' })

        result = resource_server.authorize_request!(mock_request, required_scopes: ['mcp:admin'])
        expect(result).to include(subject: 'user123')
      end

      it 'raises InvalidRequestError for invalid token' do
        allow(token_validator).to receive(:validate_token).and_return(false)

        expect { resource_server.authorize_request!(mock_request) }
          .to raise_error(FastMcp::OAuth::InvalidRequestError, 'Invalid or expired token')
      end
    end

    context 'with HTTPS requirement' do
      it 'rejects HTTP requests when HTTPS is required' do
        http_request = double('request').tap do |req|
          allow(req).to receive(:get_header) do |header|
            case header
            when 'HTTP_AUTHORIZATION'
              'Bearer valid_token'
            when 'HTTP_X_FORWARDED_PROTO'
              'http'
            when 'rack.url_scheme'
              'http'
            when 'REMOTE_ADDR'
              '192.168.1.100' # Non-localhost
            end
          end
        end

        server = described_class.new(authorization_servers, require_https: true)

        expect { server.authorize_request!(http_request) }
          .to raise_error(FastMcp::OAuth::InvalidRequestError, 'HTTPS required for OAuth requests')
      end
    end
  end

  describe '#scope?' do
    let(:mock_request) { double('request') }

    it 'returns true when token has required scope' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('Bearer valid_token')
      allow(token_validator).to receive(:validate_token).with('valid_token', required_scopes: ['mcp:read']).and_return(true)

      expect(resource_server.scope?(mock_request, 'mcp:read')).to be(true)
    end

    it 'returns false when token lacks required scope' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('Bearer valid_token')
      allow(token_validator).to receive(:validate_token).with('valid_token', required_scopes: ['mcp:admin']).and_return(false)

      expect(resource_server.scope?(mock_request, 'mcp:admin')).to be(false)
    end

    it 'returns false when no token is present' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return(nil)

      expect(resource_server.scope?(mock_request, 'mcp:read')).to be(false)
    end
  end

  describe '#oauth_error_response' do
    it 'generates invalid_token error response' do
      response = resource_server.oauth_error_response('invalid_token', 'Token has expired')

      expect(response[0]).to eq(401)
      expect(response[1]['WWW-Authenticate']).to include('Bearer error="invalid_token"')
      expect(response[1]['Content-Type']).to eq('application/json')

      body = JSON.parse(response[2].first)
      expect(body['error']).to eq('invalid_token')
      expect(body['error_description']).to eq('Token has expired')
    end

    it 'generates insufficient_scope error response' do
      response = resource_server.oauth_error_response('insufficient_scope', 'Missing mcp:admin scope', 403)

      expect(response[0]).to eq(403)
      expect(response[1]['WWW-Authenticate']).to include('Bearer error="insufficient_scope"')

      body = JSON.parse(response[2].first)
      expect(body['error']).to eq('insufficient_scope')
      expect(body['error_description']).to eq('Missing mcp:admin scope')
    end
  end

  describe 'token extraction' do
    let(:mock_request) { double('request') }

    it 'extracts Bearer token' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('Bearer abc123')
      token = resource_server.send(:extract_bearer_token, mock_request)
      expect(token).to eq('abc123')
    end

    it 'requires Bearer prefix' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('abc123def')
      token = resource_server.send(:extract_bearer_token, mock_request)
      expect(token).to be_nil
    end

    it 'returns nil for invalid authorization header' do
      allow(mock_request).to receive(:get_header).with('HTTP_AUTHORIZATION').and_return('Bearer invalid@token!')
      token = resource_server.send(:extract_bearer_token, mock_request)
      expect(token).to be_nil
    end
  end
end
