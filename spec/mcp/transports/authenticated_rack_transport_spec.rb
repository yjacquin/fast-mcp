# frozen_string_literal: true

RSpec.describe FastMcp::Transports::AuthenticatedRackTransport do
  let(:app) do
    Rack::Builder.app do
      run ->(_env) { [200, FastMcp::Transports::RackTransport::Header.new.merge({ 'Content-Type' => 'text/plain' }), ['OK']] }
    end
  end

  let(:server) do
    instance_double(FastMcp::Server, 
      logger: Logger.new(nil), 
      transport: nil,
      'transport=' => nil,
      contains_filters?: false,
      handle_request: nil  # handle_request doesn't return anything, it sends through transport
    )
  end
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

  let(:transport_app) do
    app = Rack::Builder.new
    app.use Rack::Lint
    app.run transport
    app.to_app
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
    context 'with valid authentication' do
      it 'passes the request to parent when token is valid for non-MCP paths' do
        env = Rack::MockRequest.env_for('/not-mcp', 'HTTP_AUTHORIZATION' => "Bearer #{auth_token}")

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_default_ok_response
      end

      it 'passes MCP path requests to parent class when authentication succeeds' do
        # Create a request with valid authentication
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'test', id: 1 })
        env = Rack::MockRequest.env_for(
            'https://localhost/mcp/messages', 
            method: 'POST',
            'CONTENT_TYPE' => 'application/json',
            input: request_body,
            'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
            'REMOTE_ADDR' => '127.0.0.1'
            )
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end

      it 'passes SSE requests to parent class when authentication succeeds' do
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/sse',
          method: 'GET',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.hijack?' => true
        )
        
        read_io, write_io = IO.pipe
        env['rack.hijack'] = -> { write_io }
        env['rack.hijack_io'] = write_io # for rack < 3

        result = Rack::MockResponse[*transport_app.call(env)]

        # Just verify it returns the async response format, details tested in parent
         # The result should be [-1, {}, []] for async response
         expect(result.status).to eq(200)
         expect(result.headers).to be_empty
         expect(result.body).to be_empty
         
         # Clean up
         read_io.close unless read_io.closed?
         write_io.close unless write_io.closed?
      end
    end

    context 'with invalid authentication' do
      it 'returns 401 when token is invalid' do
        env = Rack::MockRequest.env_for(
            'https://localhost/mcp/messages', 
            method: 'POST',
            'CONTENT_TYPE' => 'application/json',
            'HTTP_AUTHORIZATION' => "Bearer invalid-token",
            'REMOTE_ADDR' => '127.0.0.1'
            )
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_000).with_message('Unauthorized: Invalid or missing authentication token').with_status(401)
      end

      it 'returns 401 when token is missing' do
        env = Rack::MockRequest.env_for(
            'https://localhost/mcp/messages', 
            method: 'POST',
            'CONTENT_TYPE' => 'application/json',
            'REMOTE_ADDR' => '127.0.0.1'
            )
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_000).with_message('Unauthorized: Invalid or missing authentication token').with_status(401)
      end
    end

    context 'with exempt paths' do
      it 'skips authentication for exempt paths' do
        env = Rack::MockRequest.env_for('/public/index.html')
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_default_ok_response
      end

      it 'skips authentication for paths starting with exempt prefixes' do
        env = Rack::MockRequest.env_for('/public/assets/styles.css')
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_default_ok_response
      end

      it 'processes exempt MCP paths without authentication' do
        env = Rack::MockRequest.env_for('http://localhost/mcp/health', 'REMOTE_ADDR' => '127.0.0.1')
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32601).with_message('Endpoint not found').with_status(404)
      end
    end

    context 'with custom header name' do
      let(:auth_header_name) { 'X-Api-Key' }

      it 'accepts token from custom header' do
        env = Rack::MockRequest.env_for('/not-mcp', 'HTTP_X_API_KEY' => "Bearer #{auth_token}")
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_default_ok_response
      end
    end

    context 'with header format variations' do
      it 'accepts token without Bearer prefix' do
        env = Rack::MockRequest.env_for('/not-mcp', 'HTTP_AUTHORIZATION' => auth_token)
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_default_ok_response
      end

      it 'handles header with hyphens correctly' do
        custom_transport = described_class.new(
          app,
          server,
          logger: logger,
          auth_token: auth_token,
          auth_header_name: 'X-Custom-Auth'
        )
        app = Rack::Builder.app do
          use Rack::Lint
          run custom_transport
        end

        env = Rack::MockRequest.env_for('/not-mcp', 'HTTP_X_CUSTOM_AUTH' => "Bearer #{auth_token}")
        result = Rack::MockResponse[*app.call(env)]
        expect(result).to be_default_ok_response
      end

      it 'properly converts hyphenated header names to Rack format' do
        custom_transport = described_class.new(
          app,
          server,
          logger: logger,
          auth_token: auth_token,
          auth_header_name: 'X-Custom-Auth-Token'
        )
        app = Rack::Builder.app do
          use Rack::Lint
          run custom_transport
        end

        env = Rack::MockRequest.env_for('/not-mcp', 'HTTP_X_CUSTOM_AUTH_TOKEN' => "Bearer #{auth_token}")
        result = Rack::MockResponse[*app.call(env)]
        expect(result).to be_default_ok_response
      end
    end

    context 'with request ID extraction' do
      it 'includes request ID in unauthorized response for JSON-RPC requests' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'test', id: 123 })
        env = Rack::MockRequest.env_for(
          '/mcp/messages',
          method: 'POST',
          input: request_body,
          'CONTENT_TYPE' => 'application/json',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_000).with_message('Unauthorized: Invalid or missing authentication token').with_id(123).with_status(401)
      end

      it 'handles malformed JSON in request body gracefully' do
        env = Rack::MockRequest.env_for(
          '/mcp/messages',
          method: 'POST',
          'CONTENT_TYPE' => 'application/json',
          input: 'invalid-json',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_000).with_message('Unauthorized: Invalid or missing authentication token').with_status(401)
      end
    end

    context 'with authentication disabled' do
      let(:transport) { described_class.new(app, server,logger: logger) }

      it 'skips authentication when disabled' do
        env = Rack::MockRequest.env_for('/not-mcp')
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_default_ok_response
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
        # Test that authentication is checked before origin validation
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'POST',
          input: request_body,
          'CONTENT_TYPE' => 'application/json',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end

      it 'rejects requests with disallowed origin when authenticated' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://evil-site.com/mcp/messages',
          method: 'POST',
          input: request_body,
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}"
        )

        t = described_class.new(
          app,
          server,
          logger: logger,
          auth_token: auth_token,
          auth_header_name: auth_header_name,
          auth_exempt_paths: auth_exempt_paths
        )

        app = Rack::Builder.app do
          use Rack::Lint
          run t
        end

        result = Rack::MockResponse[*app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_600).with_message('Forbidden: Origin validation failed').with_status(403)
      end

      it 'rejects requests with disallowed ips when authenticated' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'POST',
          input: request_body,
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.2',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}"
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_600).with_message('Forbidden: Remote IP not allowed').with_status(403)
      end

      it 'checks authentication before validating origin' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://evil-site.com/mcp/messages',
          method: 'POST',
          input: request_body,
          "CONTENT_TYPE" => "application/json",
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_000).with_message('Unauthorized: Invalid or missing authentication token').with_id(1).with_status(401)
      end
    end
  end
end
