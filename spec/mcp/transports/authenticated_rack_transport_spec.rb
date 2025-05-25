# frozen_string_literal: true

RSpec.describe FastMcp::Transports::AuthenticatedRackTransport do
  let(:server) { instance_double(FastMcp::Server, logger: Logger.new(nil)) }
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:logger) { Logger.new(nil) }
  let(:auth_token) { 'valid-token-123' }
  let(:auth_header_name) { 'Authorization' }
  let(:auth_exempt_paths) { ['/public', '/mcp/health'] }

  let(:transport) do
    described_class.new(
      app,
      server,
      logger: logger,
      auth_token: auth_token,
      auth_header_name: auth_header_name,
      auth_exempt_paths: auth_exempt_paths
    )
  end

  describe '#initialize' do
    it 'initializes with authentication options' do
      expect(transport.instance_variable_get(:@auth_token)).to eq(auth_token)
      expect(transport.instance_variable_get(:@auth_header_name)).to eq(auth_header_name)
      expect(transport.instance_variable_get(:@auth_exempt_paths)).to eq(auth_exempt_paths)
      expect(transport.instance_variable_get(:@auth_enabled)).to be(true)
    end

    it 'disables authentication when no token is provided' do
      no_auth_transport = described_class.new(server, app, logger: logger)
      expect(no_auth_transport.instance_variable_get(:@auth_enabled)).to be(false)
    end

    it 'uses default header name when not specified' do
      custom_transport = described_class.new(server, app, auth_token: auth_token, logger: logger)
      expect(custom_transport.instance_variable_get(:@auth_header_name)).to eq('Authorization')
    end

    it 'uses default empty array for exempt paths when not specified' do
      custom_transport = described_class.new(server, app, auth_token: auth_token, logger: logger)
      expect(custom_transport.instance_variable_get(:@auth_exempt_paths)).to eq([])
    end
  end

  describe '#call' do
    let(:client_id) { 'test-client-id' }
    let(:context) { { client_id: client_id } }
    context 'with valid authentication' do
      it 'passes the request to parent when token is valid for non-MCP paths' do
        env = {
          'PATH_INFO' => '/not-mcp',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}"
        }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end

      it 'passes MCP path requests to parent class when authentication succeeds' do
        json_message = '{"jsonrpc":"2.0","method":"test","id":1}'
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(json_message),
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'QUERY_STRING' => "client_id=#{client_id}"
        }

        expect(server).to receive(:transport=).with(transport)

        # The RackTransport class will call server.handle_json_request with the message
        json_response = '{"jsonrpc":"2.0","result":{},"id":1}'
        expect(server).to receive(:handle_json_request).with(json_message, context).and_return(json_response)

        # For MCP paths, we don't expect app.call to be invoked
        expect(app).not_to receive(:call)

        # We're only testing that authentication passes through the request to the parent
        result = transport.call(env)
        expect(result[0]).to eq(200)
        expect(result[1]).to include('Content-Type' => 'application/json')
      end

      it 'passes SSE requests to parent class when authentication succeeds' do
        env = {
          'PATH_INFO' => '/mcp/sse',
          'REQUEST_METHOD' => 'GET',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.hijack?' => true,
          'rack.hijack' => -> {}
        }

        # Mock the hijack IO
        io = double('io')
        allow(io).to receive(:write)
        allow(io).to receive(:closed?).and_return(false)
        allow(io).to receive(:flush)
        allow(io).to receive(:close)
        env['rack.hijack_io'] = io
        allow(env['rack.hijack']).to receive(:call)

        expect(server).to receive(:transport=).with(transport)
        # Since we're testing the auth layer passes to parent, we don't expect app.call
        expect(app).not_to receive(:call)

        result = transport.call(env)

        # Just verify it returns the async response format, details tested in parent
        expect(result[0]).to eq(-1)
      end
    end

    context 'with invalid authentication' do
      it 'returns 401 when token is invalid' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token'
        }

        expect(server).to receive(:transport=).with(transport)
        result = transport.call(env)
        expect(result[0]).to eq(401)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_000)
        expect(response['error']['message']).to include('Unauthorized')
      end

      it 'returns 401 when token is missing' do
        env = { 'PATH_INFO' => '/mcp/messages' }

        expect(server).to receive(:transport=).with(transport)
        result = transport.call(env)
        expect(result[0]).to eq(401)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_000)
        expect(response['error']['message']).to include('Unauthorized')
      end
    end

    context 'with exempt paths' do
      it 'skips authentication for exempt paths' do
        env = { 'PATH_INFO' => '/public/index.html' }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end

      it 'skips authentication for paths starting with exempt prefixes' do
        env = { 'PATH_INFO' => '/public/assets/styles.css' }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end

      it 'processes exempt MCP paths without authentication' do
        env = {
          'PATH_INFO' => '/mcp/health',
          'REMOTE_ADDR' => '127.0.0.1',
          'REQUEST_METHOD' => 'GET'
        }

        # For exempt paths, the parent auth check is bypassed, but we should expect
        # the parent class to return a 404 for unknown MCP endpoints
        expect(server).to receive(:transport=).with(transport)

        # We expect the app not to be called directly
        expect(app).not_to receive(:call)

        # We're testing that the method doesn't return an auth error (401)
        result = transport.call(env)
        expect(result[0]).to eq(404)
        expect(result[1]).to include('Content-Type' => 'application/json')

        response = JSON.parse(result[2].first)
        expect(response['error']['code']).to eq(-32_601) # Method not found error
        expect(response['error']['message']).to include('Endpoint not found')
      end
    end

    context 'with custom header name' do
      let(:auth_header_name) { 'X-Api-Key' }

      it 'accepts token from custom header' do
        env = {
          'PATH_INFO' => '/not-mcp',
          'HTTP_X_API_KEY' => "Bearer #{auth_token}"
        }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end
    end

    context 'with header format variations' do
      it 'accepts token without Bearer prefix' do
        env = {
          'PATH_INFO' => '/not-mcp',
          'HTTP_AUTHORIZATION' => auth_token
        }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end

      it 'handles header with hyphens correctly' do
        custom_transport = described_class.new(
          app,
          server,
          logger: logger,
          auth_token: auth_token,
          auth_header_name: 'X-Custom-Auth'
        )

        env = {
          'PATH_INFO' => '/not-mcp',
          'HTTP_X_CUSTOM_AUTH' => "Bearer #{auth_token}"
        }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = custom_transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end

      it 'properly converts hyphenated header names to Rack format' do
        custom_transport = described_class.new(
          app,
          server,
          logger: logger,
          auth_token: auth_token,
          auth_header_name: 'X-Custom-Auth-Token'
        )

        env = {
          'PATH_INFO' => '/not-mcp',
          'HTTP_X_CUSTOM_AUTH_TOKEN' => "Bearer #{auth_token}"
        }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = custom_transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end
    end

    context 'with request ID extraction' do
      it 'includes request ID in unauthorized response for JSON-RPC requests' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'test', id: 123 })
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'rack.input' => StringIO.new(request_body)
        }

        expect(server).to receive(:transport=).with(transport)
        result = transport.call(env)
        expect(result[0]).to eq(401)

        response = JSON.parse(result[2].first)
        expect(response['id']).to eq(123)
      end

      it 'handles malformed JSON in request body gracefully' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'rack.input' => StringIO.new('invalid-json')
        }

        expect(server).to receive(:transport=).with(transport)
        result = transport.call(env)
        expect(result[0]).to eq(401)

        response = JSON.parse(result[2].first)
        expect(response['id']).to be_nil
      end
    end

    context 'with authentication disabled' do
      let(:transport) { described_class.new(app, server,logger: logger) }

      it 'skips authentication when disabled' do
        env = { 'PATH_INFO' => '/not-mcp' }

        expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])
        result = transport.call(env)
        expect(result).to eq([200, {}, ['OK']])
      end
    end

    context 'with DNS rebinding protection' do
      let(:allowed_origins) { ['localhost', '127.0.0.1', 'example.com', /.*\.example\.com/] }
      let(:transport) do
        described_class.new(
          app,
          server,
          logger: logger,
          auth_token: auth_token,
          allowed_origins: allowed_origins
        )
      end

      it 'accepts requests with allowed origin when authenticated' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://localhost',
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}'),
          'QUERY_STRING' => "client_id=#{client_id}"
        }

        expect(server).to receive(:transport=).with(transport)
        expect(server).to receive(:handle_json_request)
          .with('{"jsonrpc":"2.0","method":"ping","id":1}', context)
          .and_return('{"jsonrpc":"2.0","result":{},"id":1}')

        result = transport.call(env)
        expect(result[0]).to eq(200)
      end

      it 'rejects requests with disallowed origin when authenticated' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://evil-site.com',
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        expect(server).to receive(:transport=).with(transport)
        # The server should NOT receive handle_json_request for a disallowed origin
        expect(server).not_to receive(:handle_json_request)

        result = transport.call(env)
        expect(result[0]).to eq(403)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_600)
        expect(response['error']['message']).to include('Origin validation failed')
      end

      it 'rejects requests with disallowed ips when authenticated' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://localhost',
          'REMOTE_ADDR' => '127.0.0.2',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        expect(server).to receive(:transport=).with(transport)
        # The server should NOT receive handle_json_request for a disallowed origin
        expect(server).not_to receive(:handle_json_request)

        result = transport.call(env)
        expect(result[0]).to eq(403)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_600)
        expect(response['error']['message']).to include('Forbidden: Remote IP not allowed')
      end

      it 'checks authentication before validating origin' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://evil-site.com',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        expect(server).to receive(:transport=).with(transport)

        # Should not reach the origin validation since auth fails first
        result = transport.call(env)
        expect(result[0]).to eq(401) # Unauthorized, not 403 Forbidden

        response = JSON.parse(result[2].first)
        expect(response['error']['message']).to include('Unauthorized')
      end
    end
  end
end
