# frozen_string_literal: true

RSpec.describe FastMcp::Transports::OAuthStreamableHttpTransport do
  let(:logger) { Logger.new(nil) }
  let(:server) do
    instance_double(FastMcp::Server,
                    logger: logger,
                    transport: nil,
                    'transport=': nil,
                    contains_filters?: false,
                    handle_request: ['test response'])
  end
  let(:app) { ->(env) { [404, {}, ['Not Found']] } }

  let(:oauth_server) { instance_double(FastMcp::OAuth::ResourceServer) }
  let(:transport) do
    allow(FastMcp::OAuth::ResourceServer).to receive(:new).and_return(oauth_server)
    described_class.new(app, server, logger: logger, oauth_enabled: true)
  end

  describe '#initialize' do
    it 'initializes with OAuth enabled by default' do
      expect(transport.oauth_enabled).to be(true)
      expect(transport.scope_requirements).to include(
        tools: 'mcp:tools',
        resources: 'mcp:read',
        admin: 'mcp:admin'
      )
    end

    it 'allows OAuth to be disabled' do
      transport = described_class.new(app, server, oauth_enabled: false)
      expect(transport.oauth_enabled).to be(false)
    end

    it 'accepts custom scope requirements' do
      transport = described_class.new(app, server,
                                      tools_scope: 'custom:tools',
                                      resources_scope: 'custom:read')
      expect(transport.scope_requirements).to include(
        tools: 'custom:tools',
        resources: 'custom:read'
      )
    end
  end

  describe 'OAuth authorization' do
    context 'with valid OAuth token' do
      let(:token_info) do
        {
          subject: 'user123',
          scopes: ['mcp:read', 'mcp:tools'],
          client_id: 'client123'
        }
      end

      before do
        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
      end

      it 'allows requests with valid OAuth token' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid_token',
          'REMOTE_ADDR' => '127.0.0.1'
        }

        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'processes POST requests with OAuth validation' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'tools/list', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid_token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        # Mock server to verify OAuth info is passed in headers
        expect(server).to receive(:handle_request) do |body, headers:|
          expect(headers['oauth-subject']).to eq('user123')
          expect(headers['oauth-scopes']).to eq('mcp:read mcp:tools')
          expect(headers['oauth-client-id']).to eq('client123')
          ['response']
        end

        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end
    end

    context 'with invalid OAuth token' do
      before do
        allow(oauth_server).to receive(:authorize_request!)
          .and_raise(FastMcp::OAuth::ResourceServer::UnauthorizedError, 'Invalid token')
        allow(oauth_server).to receive(:oauth_error_response)
          .and_return({
            status: 401,
            headers: { 'Content-Type' => 'application/json', 'WWW-Authenticate' => 'Bearer error="invalid_token"' },
            body: JSON.generate({ error: { code: -32_000, message: 'Invalid token' } })
          })
      end

      it 'returns 401 for invalid OAuth token' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer invalid_token',
          'REMOTE_ADDR' => '127.0.0.1'
        }

        status, headers, body = transport.call(env)
        expect(status).to eq(401)
        expect(headers['WWW-Authenticate']).to include('Bearer error="invalid_token"')
      end
    end

    context 'with insufficient scope' do
      let(:token_info) do
        {
          subject: 'user123',
          scopes: ['mcp:read'], # Missing mcp:tools scope
          client_id: 'client123'
        }
      end

      before do
        allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
      end

      it 'returns 403 for insufficient scope on tools methods' do
        # Mock the oauth_error_response method that will be called
        allow(oauth_server).to receive(:oauth_error_response)
          .with('insufficient_scope', 'Required scope: mcp:tools', 403)
          .and_return({
            status: 403,
            headers: { 'Content-Type' => 'application/json' },
            body: JSON.generate({
              jsonrpc: '2.0',
              error: { code: -32_000, message: 'Required scope: mcp:tools' },
              id: nil
            })
          })

        request_body = JSON.generate({ jsonrpc: '2.0', method: 'tools/call', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid_token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        status, headers, body = transport.call(env)
        expect(status).to eq(403)

        response_body = JSON.parse(body.first)
        expect(response_body['error']['message']).to include('Required scope: mcp:tools')
      end

      it 'allows requests to methods within scope' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'resources/list', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer valid_token',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end
    end

    context 'with OAuth disabled' do
      let(:transport) do
        described_class.new(app, server, logger: logger, oauth_enabled: false)
      end

      it 'allows requests without OAuth validation' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '127.0.0.1'
        }

        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'processes requests normally without OAuth headers' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'tools/list', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }

        expect(server).to receive(:handle_request) do |body, headers:|
          expect(headers['oauth-subject']).to be_nil
          ['response']
        end

        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end
    end
  end

  describe 'scope-based method authorization' do
    let(:token_info) do
      {
        subject: 'user123',
        scopes: ['mcp:read', 'mcp:tools'],
        client_id: 'client123'
      }
    end

    before do
      allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
    end

    it 'determines correct scope for tools methods' do
      required_scope = transport.send(:determine_required_scope, { 'method' => 'tools/call' })
      expect(required_scope).to eq('mcp:tools')
    end

    it 'determines correct scope for resources methods' do
      required_scope = transport.send(:determine_required_scope, { 'method' => 'resources/read' })
      expect(required_scope).to eq('mcp:read')
    end

    it 'requires no scope for basic methods' do
      required_scope = transport.send(:determine_required_scope, { 'method' => 'ping' })
      expect(required_scope).to be_nil
    end

    it 'requires admin scope for unknown methods' do
      required_scope = transport.send(:determine_required_scope, { 'method' => 'unknown/method' })
      expect(required_scope).to eq('mcp:admin')
    end
  end

  describe 'SSE OAuth integration' do
    let(:token_info) do
      {
        subject: 'user123',
        scopes: ['mcp:read'],
        client_id: 'client123',
        expires_at: Time.now + 3600
      }
    end

    before do
      allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
    end

    it 'validates OAuth for SSE connections' do
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/mcp',
        'HTTP_ACCEPT' => 'text/event-stream',
        'HTTP_AUTHORIZATION' => 'Bearer valid_token',
        'REMOTE_ADDR' => '127.0.0.1'
      }

      status, headers, _body = transport.call(env)
      expect(status).to eq(200)
      expect(headers['Content-Type']).to include('text/event-stream')
    end

    it 'rejects SSE connections with insufficient scope' do
      token_info_limited = token_info.dup
      token_info_limited[:scopes] = ['mcp:write'] # Missing mcp:read
      allow(oauth_server).to receive(:authorize_request!).and_return(token_info_limited)

      # Mock the oauth_error_response method
      allow(oauth_server).to receive(:oauth_error_response)
        .with('insufficient_scope', 'Required scope: mcp:read', 403)
        .and_return({
          status: 403,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
            jsonrpc: '2.0',
            error: { code: -32_000, message: 'Required scope: mcp:read' },
            id: nil
          })
        })

      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/mcp',
        'HTTP_ACCEPT' => 'text/event-stream',
        'HTTP_AUTHORIZATION' => 'Bearer valid_token',
        'REMOTE_ADDR' => '127.0.0.1'
      }

      status, _headers, body = transport.call(env)
      expect(status).to eq(403)

      response_body = JSON.parse(body.first)
      expect(response_body['error']['message']).to include('Required scope: mcp:read')
    end
  end

  describe 'integration with parent transport features' do
    let(:token_info) do
      {
        subject: 'user123',
        scopes: ['mcp:read', 'mcp:tools', 'mcp:admin'],
        client_id: 'client123'
      }
    end

    before do
      allow(oauth_server).to receive(:authorize_request!).and_return(token_info)
    end

    it 'maintains all security validations from parent transport' do
      # Test that Origin validation still works with OAuth
      env = {
        'REQUEST_METHOD' => 'OPTIONS',
        'PATH_INFO' => '/mcp',
        'HTTP_AUTHORIZATION' => 'Bearer valid_token',
        'HTTP_ORIGIN' => 'http://evil.com',
        'REMOTE_ADDR' => '127.0.0.1'
      }

      status, _headers, body = transport.call(env)
      expect(status).to eq(403) # Origin validation failure, not OAuth failure

      response_body = JSON.parse(body.first)
      expect(response_body['error']['message']).to include('Origin validation failed')
    end

    it 'maintains protocol version validation' do
      env = {
        'REQUEST_METHOD' => 'OPTIONS',
        'PATH_INFO' => '/mcp',
        'HTTP_AUTHORIZATION' => 'Bearer valid_token',
        'HTTP_MCP_PROTOCOL_VERSION' => '2024-11-05',
        'REMOTE_ADDR' => '127.0.0.1'
      }

      status, _headers, body = transport.call(env)
      expect(status).to eq(400) # Protocol version error

      response_body = JSON.parse(body.first)
      expect(response_body['error']['data']['expected_version']).to eq('2025-06-18')
    end
  end
end
