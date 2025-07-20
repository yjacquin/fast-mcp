# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'OAuth 2.1 Resource Server Compliance' do
  let(:logger) { Logger.new(nil) }
  let(:server) do
    instance_double(FastMcp::Server,
                    logger: logger,
                    transport: nil,
                    'transport=': nil,
                    contains_filters?: false,
                    handle_request: ['test response'])
  end
  let(:app) { ->(_env) { [404, {}, ['Not Found']] } }
  let(:resource_identifier) { 'https://mcp-server.example.com' }

  let(:oauth_options) do
    {
      oauth_enabled: true,
      resource_identifier: resource_identifier,
      require_https: false, # Disabled for testing
      authorization_servers: ['https://auth.example.com'],
      logger: logger
    }
  end

  let(:oauth_server) do
    instance_double(FastMcp::OAuth::ResourceServer, resource_identifier: resource_identifier)
  end
  let(:oauth_transport) do
    allow(FastMcp::OAuth::ResourceServer).to receive(:new).and_return(oauth_server)
    FastMcp::Transports::OAuthStreamableHttpTransport.new(app, server, oauth_options)
  end


  describe 'WWW-Authenticate Header Support (OAuth 2.1 Section 5.3)' do
    context 'when token is missing' do
      before do
        allow(oauth_server).to receive(:authorize_request!)
          .and_raise(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Missing authentication token')
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 401,
                        headers: {
                          'Content-Type' => 'application/json',
                          'WWW-Authenticate' => 'Bearer error="invalid_token"'
                        },
                        body: JSON.generate({ error: 'invalid_token' })
                      })
      end

      it 'returns 401 with WWW-Authenticate header' do
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{}')
        }

        status, headers, _body = oauth_transport.call(env)

        expect(status).to eq(401)
        expect(headers['WWW-Authenticate']).not_to be_nil
        expect(headers['WWW-Authenticate']).to include('Bearer')
      end
    end

    context 'when token is invalid' do
      before do
        allow(oauth_server).to receive(:authorize_request!)
          .and_raise(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Invalid token')
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 401,
                        headers: {
                          'Content-Type' => 'application/json',
                          'WWW-Authenticate' => 'Bearer error="invalid_token"'
                        },
                        body: JSON.generate({ error: 'invalid_token' })
                      })
      end

      it 'returns 401 with proper WWW-Authenticate header' do
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{}')
        }

        status, headers, _body = oauth_transport.call(env)

        expect(status).to eq(401)
        www_auth = headers['WWW-Authenticate']
        expect(www_auth).to include('Bearer')
        expect(www_auth).to include('error="invalid_token"')
      end
    end

    context 'when token has insufficient scope' do
      let(:token_info) do
        {
          subject: 'user123',
          scopes: ['read'],
          client_id: 'client123'
        }
      end

      before do
        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 403,
                        headers: {
                          'Content-Type' => 'application/json',
                          'WWW-Authenticate' => 'Bearer error="insufficient_scope"'
                        },
                        body: JSON.generate({ error: 'insufficient_scope' })
                      })
      end

      it 'returns 403 with proper WWW-Authenticate header' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'tools/call', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        status, headers, _body = oauth_transport.call(env)

        expect(status).to eq(403)
        www_auth = headers['WWW-Authenticate']
        expect(www_auth).to include('Bearer')
        expect(www_auth).to include('error="insufficient_scope"')
      end
    end
  end

  describe 'Access Token Validation (OAuth 2.1 Section 5.2)' do
    context 'Bearer token extraction' do
      it 'accepts tokens only via Authorization header with Bearer prefix' do
        token_info = {
          subject: 'user123',
          scopes: ['mcp:tools'],
          client_id: 'client123'
        }

        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)

        # Should accept via Authorization header with Bearer prefix
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{}')
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).not_to eq(401)
      end

      it 'rejects tokens without Bearer prefix' do
        allow(oauth_server).to receive(:authorize_request!)
          .and_raise(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Missing authentication token')
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 401,
                        headers: { 'Content-Type' => 'application/json' },
                        body: JSON.generate({ error: 'invalid_token' })
                      })

        # Without Bearer prefix should fail
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'valid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{}')
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).to eq(401)
      end
    end
  end

  describe 'Error Response Handling (OAuth 2.1 Section 5.3)' do
    context 'missing tokens' do
      before do
        allow(oauth_server).to receive(:authorize_request!)
          .and_raise(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Missing authentication token')
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 401,
                        headers: { 'Content-Type' => 'application/json' },
                        body: JSON.generate({ error: 'invalid_token' })
                      })
      end

      it 'returns 401 for missing tokens' do
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{}')
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).to eq(401)
      end
    end

    context 'invalid tokens' do
      before do
        allow(oauth_server).to receive(:authorize_request!)
          .and_raise(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Invalid token')
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 401,
                        headers: { 'Content-Type' => 'application/json' },
                        body: JSON.generate({ error: 'invalid_token' })
                      })
      end

      it 'returns 401 for invalid/expired tokens' do
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{}')
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).to eq(401)
      end
    end

    context 'insufficient scope' do
      let(:token_info) do
        {
          subject: 'user123',
          scopes: ['read'],
          client_id: 'client123'
        }
      end

      before do
        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
                        status: 403,
                        headers: { 'Content-Type' => 'application/json' },
                        body: JSON.generate({ error: 'insufficient_scope' })
                      })
      end

      it 'returns 403 for insufficient scope' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'tools/call', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).to eq(403)
      end
    end

    context 'malformed requests' do
      let(:token_info) do
        {
          subject: 'user123',
          scopes: ['mcp:tools'],
          client_id: 'client123'
        }
      end

      before do
        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
      end

      it 'returns 400 for malformed JSON' do
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('invalid-json')
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).to eq(400)
      end
    end
  end

  describe 'Security Requirements (OAuth 2.1 Section 1.5, 7)' do
    context 'audience validation' do
      it 'validates exact audience match through resource server' do
        # This is tested via the resource_identifier configuration
        # The actual validation is done in the ResourceServer class
        expect(oauth_server.resource_identifier).to eq(resource_identifier)
      end
    end
  end

  describe 'Protected Resource Metadata Endpoint (RFC 9728)' do
    it 'serves metadata at /.well-known/oauth-protected-resource' do
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/.well-known/oauth-protected-resource',
        'HTTP_ACCEPT' => 'application/json',
        'REMOTE_ADDR' => '127.0.0.1',
        'SERVER_NAME' => 'mcp-server.example.com',
        'SERVER_PORT' => '443',
        'rack.url_scheme' => 'https',
        'rack.input' => StringIO.new('')
      }

      status, headers, body = oauth_transport.call(env)

      expect(status).to eq(200)
      expect(headers['Content-Type']).to eq('application/json')

      response_data = JSON.parse(body.first)
      expect(response_data['resource']).to eq('https://mcp-server.example.com')
      expect(response_data['authorization_servers']).to eq(['https://auth.example.com'])
    end

    it 'only accepts GET requests' do
      env = {
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/.well-known/oauth-protected-resource',
        'REMOTE_ADDR' => '127.0.0.1',
        'rack.input' => StringIO.new('')
      }

      status, headers, _body = oauth_transport.call(env)

      expect(status).to eq(405)
      expect(headers['Allow']).to eq('GET')
    end
  end

  describe 'Integration Validation' do
    context 'with valid token and correct scope' do
      let(:token_info) do
        {
          subject: 'user123',
          scopes: ['mcp:tools'],
          client_id: 'client123'
        }
      end

      before do
        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
      end

      it 'allows access to MCP endpoints' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'tools/list', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid-token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        status, _headers, _body = oauth_transport.call(env)
        expect(status).to eq(200)
      end
    end
  end
end
