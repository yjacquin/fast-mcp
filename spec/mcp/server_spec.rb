# frozen_string_literal: true

RSpec.describe FastMcp::Server do
  let(:server) { described_class.new(name: 'test-server', version: '1.0.0', logger: Logger.new(nil)) }

  describe '#initialize' do
    it 'creates a server with the given name and version' do
      expect(server.name).to eq('test-server')
      expect(server.version).to eq('1.0.0')
      expect(server.tools).to be_empty
    end
  end

  describe '#register_tool' do
    it 'registers a tool with the server' do
      test_tool_class = Class.new(FastMcp::Tool) do
        def self.name
          'test-tool'
        end

        def self.description
          'A test tool'
        end

        def call(**_args)
          'Hello, World!'
        end
      end

      server.register_tool(test_tool_class)

      expect(server.tools['test-tool']).to eq(test_tool_class)
    end
  end

  describe '#handle_request' do
    let(:client_id) { 'test-client-id' }
    let(:headers) { { 'client_id' => client_id } }
    let(:test_tool_class) do
      Class.new(FastMcp::Tool) do
        def self.name
          'test-tool'
        end

        def self.description
          'A test tool'
        end

        arguments do
          required(:name).filled(:string).description('User name')
        end

        def call(name:)
          "Hello, #{name}!"
        end
      end
    end

    let(:profile_tool_class) do
      Class.new(FastMcp::Tool) do
        def self.name
          'profile-tool'
        end

        def self.description
          'A tool for handling user profiles'
        end

        arguments do
          required(:user).hash do
            required(:first_name).filled(:string).description('First name of the user')
            required(:last_name).filled(:string).description('Last name of the user')
          end
        end

        def call(user:)
          "#{user[:first_name]} #{user[:last_name]}"
        end
      end
    end

    before do
      # Register the test tools
      server.register_tool(test_tool_class)
      server.register_tool(profile_tool_class)

      # Stub the send_response method
      allow(server).to receive(:send_response)
    end

    context 'with a ping request' do
      it 'responds with an empty result' do
        request = { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json

        expect(server).to receive(:send_result).with(client_id, {}, 1)
        server.handle_request(request, headers: headers)
      end
    end

    context 'with a ping response' do
      it 'responds with an empty result' do
        request = { result: {}, id: 1, jsonrpc: '2.0' }.to_json
        expect(server).not_to receive(:send_result)

        response = server.handle_request(request)
        expect(response).to be_nil
      end
    end

    context 'with a notifications/initialized request' do
      it 'responds with nil' do
        request = { jsonrpc: '2.0', method: 'notifications/initialized' }.to_json

        response = server.handle_request(request)
        expect(response).to be_nil
      end
    end

    context 'with an initialize request' do
      it 'responds with the server info' do
        request = { jsonrpc: '2.0', method: 'initialize', id: 1 }.to_json

        expect(server).to receive(:send_result).with(client_id, {
                                                       protocolVersion: FastMcp::Server::PROTOCOL_VERSION,
                                                       capabilities: server.capabilities,
                                                       serverInfo: {
                                                         name: server.name,
                                                         version: server.version
                                                       }
                                                     }, 1)
        server.handle_request(request, headers: headers)
      end
    end

    context 'with a tools/list request' do
      it 'responds with a list of tools' do
        request = { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json

        expect(server).to receive(:send_result) do |_client_id, result, id|
          expect(id).to eq(1)
          expect(result[:tools]).to be_an(Array)
          expect(result[:tools].length).to eq(2)

          # Test the simple tool
          test_tool = result[:tools].find { |t| t[:name] == 'test-tool' }
          expect(test_tool[:description]).to eq('A test tool')
          expect(test_tool[:inputSchema]).to be_a(Hash)
          expect(test_tool[:inputSchema][:properties][:name][:description]).to eq('User name')

          # Test the tool with nested properties
          profile_tool = result[:tools].find { |t| t[:name] == 'profile-tool' }
          expect(profile_tool[:description]).to eq('A tool for handling user profiles')
          expect(profile_tool[:inputSchema][:properties][:user][:type]).to eq('object')
          # We no longer expect descriptions on nested fields since they aren't being passed through
          expect(profile_tool[:inputSchema][:properties][:user][:properties]).to have_key(:first_name)
          expect(profile_tool[:inputSchema][:properties][:user][:properties]).to have_key(:last_name)
        end

        server.handle_request(request, headers: headers)
      end
    end

    context 'with a tools/call request' do
      it 'calls the specified tool and returns the result' do
        request = {
          jsonrpc: '2.0',
          method: 'tools/call',
          params: {
            name: 'test-tool',
            arguments: { name: 'World' }
          },
          id: 1
        }.to_json

        expect(server).to receive(:send_result).with(
          client_id,
          { content: [{ text: 'Hello, World!', type: 'text' }], isError: false },
          1,
          metadata: {}
        )
        server.handle_request(request, headers: headers)
      end

      it 'calls a tool with nested properties' do
        request = {
          jsonrpc: '2.0',
          method: 'tools/call',
          params: {
            name: 'profile-tool',
            arguments: {
              user: {
                first_name: 'John',
                last_name: 'Doe'
              }
            }
          },
          id: 1
        }.to_json

        expect(server).to receive(:send_result).with(
          client_id,
          { content: [{ text: 'John Doe', type: 'text' }], isError: false },
          1,
          metadata: {}
        )
        server.handle_request(request, headers: headers)
      end

      it "returns an error if the tool doesn't exist" do
        request = {
          jsonrpc: '2.0',
          method: 'tools/call',
          params: {
            name: 'non-existent-tool',
            arguments: {}
          },
          id: 1
        }.to_json

        expect(server).to receive(:send_error).with(-32_602, client_id, 'Tool not found: non-existent-tool', 1)
        server.handle_request(request, headers: headers)
      end

      it 'returns an error if the tool name is missing' do
        request = {
          jsonrpc: '2.0',
          method: 'tools/call',
          params: {
            arguments: {}
          },
          id: 1
        }.to_json

        expect(server).to receive(:send_error).with(-32_602, client_id, 'Invalid params: missing tool name', 1)
        server.handle_request(request, headers: headers)
      end
    end

    context 'with an invalid request' do
      it 'returns an error for an unknown method' do
        request = { jsonrpc: '2.0', method: 'unknown', id: 1 }.to_json

        expect(server).to receive(:send_error).with(-32_601, client_id, 'Method not found: unknown', 1)
        server.handle_request(request, headers: headers)
      end

      it 'returns an error for an invalid JSON-RPC request' do
        request = { id: 1 }.to_json

        expect(server).to receive(:send_error).with(-32_600, client_id, 'Invalid Request', 1)
        server.handle_request(request, headers: headers)
      end

      it 'returns an error for an invalid JSON request' do
        request = 'invalid json'

        expect(server).to receive(:send_error).with(-32_600, client_id, 'Invalid Request', nil)
        server.handle_request(request, headers: headers)
      end
    end
  end
end
