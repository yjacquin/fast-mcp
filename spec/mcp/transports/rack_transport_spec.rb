# frozen_string_literal: true

# This spec demonstrates the use of custom response matchers:
# - be_json_rpc_response: General matcher for any JSON-RPC 2.0 response (default: empty body)
# - be_json_rpc_error: Specific matcher for JSON-RPC error responses (chain-based)
# - be_default_ok_response: Matcher for plain text OK responses (non-JSON-RPC endpoints)
#
# Examples:
#   expect(result).to be_json_rpc_response  # Empty success response (default)
#   expect(result).to be_json_rpc_response.with_body({ 'jsonrpc' => '2.0', 'result' => data, 'id' => 1 })
#   expect(result).to be_json_rpc_error.with_error_code(-32_600).with_message('Invalid Request').with_status(400)
#   expect(result).to be_json_rpc_error.with_error_code(-32_700)  # Match by code only
#   expect(result).to be_json_rpc_error  # Match any JSON-RPC error
#   expect(result).to be_default_ok_response  # Plain text 'OK' response

RSpec.describe FastMcp::Transports::RackTransport do
  let(:app) { 
    Rack::Builder.app do
      run ->(_env) { [200, FastMcp::Transports::RackTransport::Header.new.merge({ 'Content-Type' => 'text/plain' }), ['OK']] }
    end
  }
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
  let(:transport) { described_class.new(app, server, logger: logger, localhost_only: localhost_only) }
  let(:localhost_only) { true }
  let(:transport_app) do
    app = Rack::Builder.new
    app.use Rack::Lint
    app.run transport
    app.to_app
  end




  describe '#initialize' do
    it 'initializes with server, app, and options' do
      expect(transport.server).to eq(server)
      expect(transport.app).to eq(app)
      expect(transport.logger).to eq(logger)
      expect(transport.path_prefix).to eq('/mcp')
      expect(transport.sse_clients).to eq({})
      expect(transport.localhost_only).to eq(localhost_only)
    end

    it 'accepts custom path prefix' do
      custom_transport = described_class.new(server, app, path_prefix: '/api/mcp', logger: logger)
      expect(custom_transport.path_prefix).to eq('/api/mcp')
    end
  end

  describe '#start' do
    it 'starts the transport' do
      expect(logger).to receive(:debug).with(/Starting Rack transport/)
      expect(logger).to receive(:debug).with(/DNS rebinding protection enabled/)
      transport.start
      expect(transport.instance_variable_get(:@running)).to be(true)
    end
  end

  describe '#stop' do
    it 'stops the transport and closes SSE connections' do
      # Add a mock SSE client
      client_stream = double('stream')
      expect(client_stream).to receive(:respond_to?).with(:close).and_return(true)
      expect(client_stream).to receive(:closed?).and_return(false)
      expect(client_stream).to receive(:close)

      transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream } })
      transport.instance_variable_set(:@running, true)

      expect(logger).to receive(:debug).with('Stopping Rack transport')
      transport.stop

      expect(transport.instance_variable_get(:@running)).to be(false)
      expect(transport.sse_clients).to be_empty
    end

    it 'handles errors when closing SSE connections' do
      # Add a mock SSE client that raises an error when closed
      client_stream = double('stream')
      expect(client_stream).to receive(:respond_to?).with(:close).and_return(true)
      expect(client_stream).to receive(:closed?).and_return(false)
      expect(client_stream).to receive(:close).and_raise(StandardError.new('Test error'))

      transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream } })
      transport.instance_variable_set(:@running, true)

      expect(logger).to receive(:debug).with('Stopping Rack transport')
      expect(logger).to receive(:error).with(/Error closing SSE connection/)

      transport.stop

      expect(transport.instance_variable_get(:@running)).to be(false)
      expect(transport.sse_clients).to be_empty
    end
  end

  describe '#send_message' do
    context 'with multiple clients' do
      it 'sends a message to all SSE clients' do
        # Add mock SSE clients
        client1_stream = double('stream1')
        client2_stream = double('stream2')

        expect(client1_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client1_stream).to receive(:closed?).and_return(false)
        expect(client1_stream).to receive(:write).with("data: {\"test\":\"message\"}\n\n")
        expect(client1_stream).to receive(:respond_to?).with(:flush).and_return(true)
        expect(client1_stream).to receive(:flush)

        expect(client2_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client2_stream).to receive(:closed?).and_return(false)
        expect(client2_stream).to receive(:write).with("data: {\"test\":\"message\"}\n\n")
        expect(client2_stream).to receive(:respond_to?).with(:flush).and_return(true)
        expect(client2_stream).to receive(:flush)

        transport.instance_variable_set(:@sse_clients, {
                                          'client1' => { stream: client1_stream, mutex: Mutex.new },
                                          'client2' => { stream: client2_stream, mutex: Mutex.new }
                                        })

        expect(logger).to receive(:debug).with(/Broadcasting message to 2 SSE clients/)

        transport.send_message({ test: 'message' })
      end
    end

    context 'with different message types' do
      it 'handles string messages' do
        client_stream = double('stream')
        expect(client_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client_stream).to receive(:closed?).and_return(false)
        expect(client_stream).to receive(:write).with("data: test message\n\n")
        expect(client_stream).to receive(:respond_to?).with(:flush).and_return(true)
        expect(client_stream).to receive(:flush)

        transport.instance_variable_set(:@sse_clients, {
                                          'client' => { stream: client_stream, mutex: Mutex.new }
                                        })

        expect(logger).to receive(:debug).with(/Broadcasting message to 1 SSE clients/)

        transport.send_message('test message')
      end
    end

    context 'with error handling' do
      it 'handles errors when sending to clients' do
        # Add a mock SSE client that raises an error
        client_stream = double('stream')
        expect(client_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client_stream).to receive(:closed?).and_return(false)
        expect(client_stream).to receive(:write).and_raise(StandardError.new('Test error'))

        transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream, mutex: Mutex.new } })

        expect(logger).to receive(:debug).with(/Broadcasting message to 1 SSE clients/)
        expect(logger).to receive(:error).with(/Error sending message to client test-client/)
        expect(logger).to receive(:info).with(/Unregistering SSE client: test-client/)

        transport.send_message({ test: 'message' })

        # The client should be removed after the error
        expect(transport.sse_clients).to be_empty
      end

      it 'handles errors when mutex raises exception' do
        # Add a mock SSE client that raises an error
        client_stream = double('stream')
        allow(client_stream).to receive(:respond_to?).and_return(false)
        allow(client_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        allow(client_stream).to receive(:respond_to?).with(:flush).and_return(true)
        allow(client_stream).to receive(:closed?).and_return(false)
        allow(client_stream).to receive(:write)
        allow(client_stream).to receive(:flush)

        # Create a client with a mutex that will raise an error
        client_mutex = double('mutex')
        allow(client_mutex).to receive(:synchronize).and_raise(StandardError.new('Mutex error'))

        transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream, mutex: client_mutex } })

        expect(logger).to receive(:debug).with(/Broadcasting message to 1 SSE clients/)
        expect(logger).to receive(:error).with(/Error sending message to client test-client/)
        expect(logger).to receive(:info).with(/Unregistering SSE client: test-client/)

        transport.send_message({ test: 'message' })

        # The client should be removed after the error
        expect(transport.sse_clients).to be_empty
      end
    end
  end

  describe '#call' do
    it 'passes non-MCP requests to the app' do
      env = Rack::MockRequest.env_for('/not-mcp')
      result = Rack::MockResponse[*transport_app.call(env)]
      expect(result).to be_default_ok_response
    end

    context 'with DNS rebinding protection' do
      let(:allowed_origins) { ['localhost', '127.0.0.1', 'example.com', /.*\.example\.com/] }
      let(:transport) do
        described_class.new(
          app,
          server,
          logger: logger,
          allowed_origins: allowed_origins,
          localhost_only: true,
          allowed_ips: ['127.0.0.1', '192.168.0.1']
        )
      end


      it 'accepts requests with allowed origin' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'POST',
          input: request_body,
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end

      it 'refuses requests with disallowed origin' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://disallowed.com/mcp/messages',
          method: 'POST',
          input: request_body,
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_600).with_message('Forbidden: Origin validation failed').with_status(403)
      end

      it 'refuses requests with disallowed ip' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'POST',
          input: request_body
        )

        # Create a proper request double that includes necessary methods
        request = instance_double(Rack::Request,
          ip: '127.0.0.2',
          path: '/mcp/messages',
          post?: true,
          params: {},
          body: instance_double(StringIO, read: request_body),
          host: 'localhost'
        )
        allow(Rack::Request).to receive(:new).with(env).and_return(request)

        expect(server).to receive(:transport=).with(transport)
        expect(server).to receive(:handle_json_request).never

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_600).with_message('Forbidden: Remote IP not allowed').with_status(403)
      end

      it 'accepts requests with origin matching a regex pattern' do
        # Test with an origin matching a regex
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'https://sub.example.com/mcp/messages',
          method: 'POST',
          input: request_body,
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end

      it 'rejects requests with disallowed origin' do
        # Test with a disallowed origin
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://evil-site.com/mcp/messages',
          method: 'POST',
          input: request_body,
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_600).with_message('Forbidden: Origin validation failed').with_status(403)
      end

      it 'falls back to Referer header when Origin is not present' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          '/mcp/messages',
          method: 'POST',
          input: request_body,
          'HTTP_REFERER' => 'http://localhost/some/path',
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end

      it 'falls back to Host header when Origin and Referer are not present' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://localhost:3000/mcp/messages',
          method: 'POST',
          input: request_body,
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end
    end

    it 'returns 404 for unknown MCP endpoints' do
      env = Rack::MockRequest.env_for('http://localhost/mcp/invalid-endpoint', 'REMOTE_ADDR' => '127.0.0.1')
      result = Rack::MockResponse[*transport_app.call(env)]
      expect(result).to be_json_rpc_error.with_error_code(-32_601).with_message('Endpoint not found').with_status(404)
    end

    context 'with root MCP endpoint' do
      it 'handles root MCP endpoint requests' do
        # The default route handler doesn't have a special case for root requests
        # so we expect a 404 response with "Endpoint not found" message
        env = Rack::MockRequest.env_for('http://localhost/mcp', 'REMOTE_ADDR' => '127.0.0.1')
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_601).with_message('Endpoint not found').with_status(404)
      end
    end

    context 'with SSE requests' do
      it 'handles SSE requests with rack hijack' do
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/sse?foo=example&bar=baz',
          method: 'GET',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.hijack?' => true
        )

        # Mock the hijack capabilities
        # Create a real IO object using a pipe
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

      it 'returns 405 for non-GET SSE requests' do
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/sse',
          method: 'POST',
          'REMOTE_ADDR' => '127.0.0.1'
        )
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_601).with_message('Method not allowed').with_status(405)
      end
    end

    context 'with JSON-RPC requests' do
      it 'handles valid JSON-RPC requests' do
        request_body = JSON.generate({ jsonrpc: '2.0', method: 'ping', id: 1 })
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'POST',
          input: request_body,
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1'
        )

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_response
      end

      it 'handles errors in JSON-RPC requests' do
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'POST',
          input: 'invalid json',
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1'
        )
        
        # Mock the server to return a parse error
        allow(server).to receive(:handle_request).and_raise(JSON::ParserError, 'Invalid JSON')

        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_700).with_message('Parse error: Invalid JSON').with_status(400)
      end

      it 'returns 405 for non-POST message requests' do
        env = Rack::MockRequest.env_for(
          'http://localhost/mcp/messages',
          method: 'GET',
          'REMOTE_ADDR' => '127.0.0.1'
        )
        result = Rack::MockResponse[*transport_app.call(env)]
        expect(result).to be_json_rpc_error.with_error_code(-32_601).with_message('Method not allowed').with_status(405)
      end
    end
  end

  # Tests for private methods
  describe '#validate_origin (private)' do
    let(:allowed_origins) { ['localhost', '127.0.0.1', 'example.com', /.*\.example\.com/] }
    let(:transport) { described_class.new(app, server, logger: logger, allowed_origins: allowed_origins) }

    it 'validates origins correctly' do
      request = instance_double('Rack::Request', host: 'localhost:3000')

      # Test allowed origins
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://localhost'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://127.0.0.1'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'https://example.com'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'https://sub.example.com'})).to be true

      # Test disallowed origins
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://evil.com'})).to be false
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://sub.evil.com'})).to be false
    end

    it 'falls back to referer when origin is missing' do
      request = instance_double('Rack::Request', host: 'localhost:3000')

      # Test with referer only
      expect(transport.send(:validate_origin, request, {'HTTP_REFERER' => 'http://localhost/path'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_REFERER' => 'http://evil.com/path'})).to be false
    end

    it 'falls back to host when origin and referer are missing' do
      # Test with host only (from request)
      request = instance_double('Rack::Request', host: 'localhost:3000')
      expect(transport.send(:validate_origin, request, {})).to be true

      request = instance_double('Rack::Request', host: 'evil.com:3000')
      expect(transport.send(:validate_origin, request, {})).to be false
    end
  end

  describe '#extract_hostname (private)' do
    let(:transport) { described_class.new(app, server, logger: logger) }

    it 'extracts hostname from URLs correctly' do
      expect(transport.send(:extract_hostname, 'http://localhost')).to eq('localhost')
      expect(transport.send(:extract_hostname, 'https://example.com')).to eq('example.com')
      expect(transport.send(:extract_hostname, 'http://sub.domain.example.com:8080/path')).to eq('sub.domain.example.com')
    end

    it 'handles URLs without scheme by adding a dummy scheme' do
      expect(transport.send(:extract_hostname, 'localhost')).to eq('localhost')
      expect(transport.send(:extract_hostname, 'example.com')).to eq('example.com')
      expect(transport.send(:extract_hostname, 'sub.example.com:8080')).to eq('sub.example.com')
    end

    it 'returns nil for empty or nil URLs' do
      expect(transport.send(:extract_hostname, nil)).to be_nil
      expect(transport.send(:extract_hostname, '')).to be_nil
    end

    it 'gracefully handles invalid URLs' do
      expect(transport.send(:extract_hostname, 'not a url')).to eq('not a url')
      expect(transport.send(:extract_hostname, 'http://')).to be_nil
    end
  end
end
