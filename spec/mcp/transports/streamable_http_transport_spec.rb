# frozen_string_literal: true

RSpec.describe FastMcp::Transports::StreamableHttpTransport do
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
  let(:transport) { described_class.new(app, server, logger: logger) }

  describe '#initialize' do
    it 'initializes with default values' do
      expect(transport.path).to eq('/mcp')
      expect(transport.allowed_origins).to eq(['localhost', '127.0.0.1', '[::1]'])
      expect(transport.localhost_only).to be(true)
    end

    it 'accepts custom configuration' do
      custom_transport = described_class.new(
        app, server,
        path: '/custom',
        allowed_origins: ['example.com'],
        localhost_only: false
      )

      expect(custom_transport.path).to eq('/custom')
      expect(custom_transport.allowed_origins).to eq(['example.com'])
      expect(custom_transport.localhost_only).to be(false)
    end
  end

  describe '#start and #stop' do
    it 'starts and stops the transport' do
      expect { transport.start }.not_to raise_error
      expect { transport.stop }.not_to raise_error
    end
  end

  describe 'Rack middleware behavior' do
    context 'when request is not for MCP endpoint' do
      it 'passes through to the underlying app' do
        env = { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/other-path' }
        status, headers, body = transport.call(env)
        expect(status).to eq(404)
        expect(body).to eq(['Not Found'])
      end
    end

    context 'when request is for MCP endpoint' do
      describe 'OPTIONS requests' do
        it 'handles CORS preflight requests' do
          env = {
            'REQUEST_METHOD' => 'OPTIONS',
            'PATH_INFO' => '/mcp',
            'REMOTE_ADDR' => '127.0.0.1'
          }
          status, headers, _body = transport.call(env)
          expect(status).to eq(200)
          expect(headers['Access-Control-Allow-Origin']).to eq('*')
          expect(headers['Access-Control-Allow-Methods']).to include('GET', 'POST')
        end
      end

      describe 'GET requests' do
        context 'without proper Accept header' do
          it 'returns 400 for missing SSE accept header' do
            env = {
              'REQUEST_METHOD' => 'GET',
              'PATH_INFO' => '/mcp',
              'REMOTE_ADDR' => '127.0.0.1'
            }
            status, headers, body = transport.call(env)
            expect(status).to eq(400)
            expect(headers['Content-Type']).to include('application/json')
            
            response_body = JSON.parse(body.first)
            expect(response_body['error']['code']).to eq(-32_600)
            expect(response_body['error']['message']).to include('text/event-stream')
          end
        end

        context 'with proper Accept header' do
          it 'attempts to setup SSE stream' do
            env = {
              'REQUEST_METHOD' => 'GET',
              'PATH_INFO' => '/mcp',
              'HTTP_ACCEPT' => 'text/event-stream',
              'REMOTE_ADDR' => '127.0.0.1'
            }
            status, headers, _body = transport.call(env)
            
            # Without rack.hijack support, it should return basic SSE response
            expect(status).to eq(200)
            expect(headers['Content-Type']).to include('text/event-stream')
          end
        end
      end

      describe 'POST requests' do
        context 'without proper Accept header' do
          it 'returns 400 for missing JSON accept header' do
            env = {
              'REQUEST_METHOD' => 'POST',
              'PATH_INFO' => '/mcp',
              'CONTENT_TYPE' => 'application/json',
              'REMOTE_ADDR' => '127.0.0.1',
              'rack.input' => StringIO.new(JSON.generate({ test: 'data' }))
            }
            status, _headers, body = transport.call(env)
            expect(status).to eq(400)
            
            response_body = JSON.parse(body.first)
            expect(response_body['error']['code']).to eq(-32_600)
          end
        end

        context 'with proper Accept header' do
          let(:request_body) { JSON.generate({ jsonrpc: '2.0', method: 'test', id: 1 }) }

          it 'processes JSON-RPC requests' do
            env = {
              'REQUEST_METHOD' => 'POST',
              'PATH_INFO' => '/mcp',
              'HTTP_ACCEPT' => 'application/json, text/event-stream',
              'CONTENT_TYPE' => 'application/json',
              'REMOTE_ADDR' => '127.0.0.1',
              'rack.input' => StringIO.new(request_body)
            }
            status, headers, _body = transport.call(env)

            expect(status).to eq(200)
            expect(headers['Content-Type']).to include('application/json')
          end

          it 'returns 202 for notifications (no response)' do
            allow(server).to receive(:handle_request).and_return(nil)
            
            env = {
              'REQUEST_METHOD' => 'POST',
              'PATH_INFO' => '/mcp',
              'HTTP_ACCEPT' => 'application/json, text/event-stream',
              'CONTENT_TYPE' => 'application/json',
              'REMOTE_ADDR' => '127.0.0.1',
              'rack.input' => StringIO.new(request_body)
            }
            status, _headers, _body = transport.call(env)

            expect(status).to eq(202)
          end
        end

        context 'with invalid JSON' do
          it 'returns parse error' do
            env = {
              'REQUEST_METHOD' => 'POST',
              'PATH_INFO' => '/mcp',
              'HTTP_ACCEPT' => 'application/json, text/event-stream',
              'CONTENT_TYPE' => 'application/json',
              'REMOTE_ADDR' => '127.0.0.1',
              'rack.input' => StringIO.new('invalid json')
            }
            status, _headers, body = transport.call(env)

            expect(status).to eq(400)
            response_body = JSON.parse(body.first)
            expect(response_body['error']['code']).to eq(-32_700)
            expect(response_body['error']['message']).to include('Parse error')
          end
        end
      end

      describe 'unsupported HTTP methods' do
        it 'returns 405 for PUT requests' do
          env = {
            'REQUEST_METHOD' => 'PUT',
            'PATH_INFO' => '/mcp',
            'REMOTE_ADDR' => '127.0.0.1'
          }
          status, _headers, body = transport.call(env)
          expect(status).to eq(405)
          
          response_body = JSON.parse(body.first)
          expect(response_body['error']['code']).to eq(-32_601)
          expect(response_body['error']['message']).to eq('Method not allowed')
        end
      end
    end
  end

  describe 'security features' do
    describe 'IP validation' do
      it 'allows localhost connections by default' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'blocks non-localhost connections when localhost_only is true' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '192.168.1.100'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(403)
        
        response_body = JSON.parse(body.first)
        expect(response_body['error']['message']).to include('Remote IP not allowed')
      end
    end

    describe 'Origin validation' do
      it 'allows requests from localhost origins' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_ORIGIN' => 'http://localhost:3000',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'blocks requests from disallowed origins' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_ORIGIN' => 'http://evil.com',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(403)
        
        response_body = JSON.parse(body.first)
        expect(response_body['error']['message']).to include('Origin validation failed')
      end
    end

    describe 'protocol version validation' do
      it 'accepts requests without protocol version header' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'accepts requests with correct protocol version' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_MCP_PROTOCOL_VERSION' => '2025-06-18',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, _body = transport.call(env)
        expect(status).to eq(200)
      end

      it 'rejects requests with incorrect protocol version' do
        env = {
          'REQUEST_METHOD' => 'OPTIONS',
          'PATH_INFO' => '/mcp',
          'HTTP_MCP_PROTOCOL_VERSION' => '2024-11-05',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        status, _headers, body = transport.call(env)
        expect(status).to eq(400)
        
        response_body = JSON.parse(body.first)
        expect(response_body['error']['data']['expected_version']).to eq('2025-06-18')
      end
    end
  end

  describe 'session management' do
    it 'generates secure session IDs' do
      session_id = transport.send(:generate_session_id)
      expect(session_id).to be_a(String)
      expect(session_id.length).to eq(32)
      expect(session_id).to match(/\A[a-zA-Z0-9]+\z/) # Only alphanumeric characters
    end

    it 'creates unique session IDs' do
      id1 = transport.send(:generate_session_id)
      id2 = transport.send(:generate_session_id)
      expect(id1).not_to eq(id2)
    end

    describe 'session ID validation' do
      it 'accepts valid 32-character alphanumeric session IDs' do
        valid_id = 'a1b2c3d4e5f6789012345678901234ab'
        expect(transport.send(:valid_session_id_format?, valid_id)).to be(true)
      end

      it 'rejects session IDs with invalid length' do
        short_id = 'abc123'
        long_id = 'a1b2c3d4e5f6789012345678901234abcd'
        expect(transport.send(:valid_session_id_format?, short_id)).to be(false)
        expect(transport.send(:valid_session_id_format?, long_id)).to be(false)
      end

      it 'rejects session IDs with special characters' do
        invalid_id = 'a1b2c3d4e5f6789012345678901234a!'
        expect(transport.send(:valid_session_id_format?, invalid_id)).to be(false)
      end
    end

    describe 'session tracking' do
      let(:mock_request) do
        double('request',
               params: {},
               get_header: nil,
               ip: '127.0.0.1')
      end

      before do
        allow(mock_request).to receive(:get_header).with('HTTP_USER_AGENT').and_return('Test Agent')
        allow(mock_request).to receive(:get_header).with('HTTP_X_SESSION_ID').and_return(nil)
        allow(mock_request).to receive(:get_header).with('HTTP_LAST_EVENT_ID').and_return(nil)
      end

      it 'creates session info when getting new session' do
        session_id = transport.send(:get_or_create_session, mock_request)
        
        session_info = transport.sessions[session_id]
        expect(session_info).to include(
          :created_at,
          :last_seen,
          :connections,
          :user_agent,
          :remote_ip
        )
        expect(session_info[:connections]).to eq(1)
        expect(session_info[:user_agent]).to eq('Test Agent')
        expect(session_info[:remote_ip]).to eq('127.0.0.1')
      end

      it 'updates connection count for existing sessions' do
        session_id = transport.send(:get_or_create_session, mock_request)
        initial_connections = transport.sessions[session_id][:connections]
        
        # Simulate another request with same session
        allow(mock_request).to receive(:get_header).with('HTTP_X_SESSION_ID').and_return(session_id)
        transport.send(:get_or_create_session, mock_request)
        
        expect(transport.sessions[session_id][:connections]).to eq(initial_connections + 1)
      end

      it 'rejects invalid session ID format and generates new one' do
        invalid_session_id = 'invalid-session!'
        allow(mock_request).to receive(:get_header).with('HTTP_X_SESSION_ID').and_return(invalid_session_id)
        
        new_session_id = transport.send(:get_or_create_session, mock_request)
        expect(new_session_id).not_to eq(invalid_session_id)
        expect(transport.send(:valid_session_id_format?, new_session_id)).to be(true)
      end
    end
  end

  describe '#send_message' do
    it 'handles empty client list gracefully' do
      expect { transport.send_message({ test: 'message' }) }.not_to raise_error
    end

    it 'converts hash messages to JSON' do
      message = { jsonrpc: '2.0', method: 'test' }
      expect { transport.send_message(message) }.not_to raise_error
    end

    it 'handles string messages directly' do
      message = '{"jsonrpc":"2.0","method":"test"}'
      expect { transport.send_message(message) }.not_to raise_error
    end
  end
end