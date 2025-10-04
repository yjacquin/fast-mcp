# frozen_string_literal: true

RSpec.describe FastMcp::Transports::AuthenticatedStreamableHttpTransport do
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
  let(:auth_token) { 'test-secret-token' }
  let(:transport) do
    described_class.new(app, server,
                        logger: logger,
                        auth_token: auth_token,
                        auth_header_name: 'Authorization')
  end

  describe '#initialize' do
    it 'initializes with authentication options' do
      expect(transport.auth_enabled).to be(true)
      expect(transport.auth_token).to eq(auth_token)
      expect(transport.auth_header_name).to eq('Authorization')
      expect(transport.auth_exempt_paths).to eq([])
    end

    it 'disables authentication when no token is provided' do
      transport = described_class.new(app, server, logger: logger)
      expect(transport.auth_enabled).to be(false)
    end

    it 'accepts custom header name and exempt paths' do
      transport = described_class.new(app, server,
                                      logger: logger,
                                      auth_token: auth_token,
                                      auth_header_name: 'X-API-Key',
                                      auth_exempt_paths: ['/health', '/status'])

      expect(transport.auth_header_name).to eq('X-API-Key')
      expect(transport.auth_exempt_paths).to eq(['/health', '/status'])
    end
  end

  describe 'authentication behavior' do
    context 'with valid authentication' do
      it 'allows requests with valid Bearer token' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'allows requests with valid token without Bearer prefix' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => auth_token,
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'processes POST requests with valid authentication' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'test', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end
    end

    context 'with invalid authentication' do
      it 'returns 401 for missing authorization header' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, headers, body = transport.call(env)
        expect(status).to eq(401)
        expect(headers['Content-Type']).to include('application/json')
        expect(headers['WWW-Authenticate']).to eq('Bearer realm="MCP"')

        response_body = JSON.parse(body.first)
        expect(response_body['error']['code']).to eq(-32_000)
        expect(response_body['error']['message']).to include('Unauthorized')
      end

      it 'returns 401 for invalid token' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer invalid-token',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(401)

        response_body = JSON.parse(body.first)
        expect(response_body['error']['message']).to include('Unauthorized')
      end

      it 'returns 401 for empty token' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => 'Bearer ',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(401)

        response_body = JSON.parse(body.first)
        expect(response_body['error']['message']).to include('Unauthorized')
      end

      it 'includes request ID in error response for JSON-RPC requests' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'test', id: 123 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(401)

        response_body = JSON.parse(body.first)
        expect(response_body['id']).to eq(123)
      end

      it 'handles malformed JSON gracefully' do
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('invalid json')
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(401)

        response_body = JSON.parse(body.first)
        expect(response_body['id']).to be_nil
      end
    end

    context 'with exempt paths' do
      let(:transport) do
        described_class.new(app, server,
                            logger: logger,
                            auth_token: auth_token,
                            auth_exempt_paths: ['/health', '/status'])
      end

      it 'skips authentication for exact exempt paths' do
        env = {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/health'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(404) # Passed to underlying app
        expect(body).to eq(['Not Found'])
      end

      it 'skips authentication for paths starting with exempt prefixes' do
        env = {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/health/check'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(404) # Passed to underlying app
      end

      it 'still requires authentication for non-exempt MCP paths' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(401)
      end
    end

    context 'with custom header name' do
      let(:transport) do
        described_class.new(app, server,
                            logger: logger,
                            auth_token: auth_token,
                            auth_header_name: 'X-API-Key')
      end

      it 'accepts token from custom header' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_X_API_KEY' => auth_token,
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'rejects requests without the custom header' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}", # Wrong header
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(401)
      end

      it 'handles hyphenated header names correctly' do
        transport = described_class.new(app, server,
                                        logger: logger,
                                        auth_token: auth_token,
                                        auth_header_name: 'X-Custom-Auth')

        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_X_CUSTOM_AUTH' => auth_token,
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end
    end

    context 'with authentication disabled' do
      let(:transport) do
        described_class.new(app, server, logger: logger) # No auth_token
      end

      it 'allows all requests when authentication is disabled' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'processes requests normally without authentication checks' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'test', id: 1 })
        env = {
          'REQUEST_METHOD' => 'POST',
          'PATH_INFO' => '/mcp',
          'HTTP_ACCEPT' => 'application/json, text/event-stream',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new(request_body)
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end
    end
  end

  describe 'integration with parent transport features' do
    context 'with valid authentication' do
      it 'maintains all security validations from parent' do
        # Test that Origin validation still works with authentication
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
          'HTTP_ORIGIN' => 'http://evil.com',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(403) # Origin validation failure, not auth failure

        response_body = JSON.parse(body.first)
        expect(response_body['error']['message']).to include('Origin validation failed')
      end

      it 'maintains protocol version validation' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_AUTHORIZATION' => "Bearer #{auth_token}",
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
end