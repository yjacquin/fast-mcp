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

  describe '#register_prompt' do
    it 'registers a prompt with the server' do
      test_prompt_class = Class.new(FastMcp::Prompt) do
        def self.name
          'TestPrompt'
        end

        prompt_name 'test_prompt'
        description 'A test prompt'

        def call(**_args)
          messages(user: 'Hello, World!')
        end
      end

      server.register_prompt(test_prompt_class)

      expect(server.instance_variable_get(:@prompts)['test_prompt']).to eq(test_prompt_class)
      expect(test_prompt_class.server).to eq(server)
    end

    it 'derives prompt name from class name if not explicitly set' do
      test_prompt_class = Class.new(FastMcp::Prompt) do
        def self.name
          'TestAutoPrompt'
        end

        description 'A test prompt with auto-derived name'

        def call(**_args)
          messages(user: 'Hello, World!')
        end
      end

      server.register_prompt(test_prompt_class)

      expect(server.instance_variable_get(:@prompts)['test_auto']).to eq(test_prompt_class)
    end
  end

  describe '#register_prompts' do
    it 'registers multiple prompts at once' do
      test_prompt_class1 = Class.new(FastMcp::Prompt) do
        def self.name
          'TestPrompt1'
        end

        prompt_name 'test_prompt_1'
        description 'First test prompt'

        def call(**_args)
          messages(user: 'Hello from prompt 1!')
        end
      end

      test_prompt_class2 = Class.new(FastMcp::Prompt) do
        def self.name
          'TestPrompt2'
        end

        prompt_name 'test_prompt_2'
        description 'Second test prompt'

        def call(**_args)
          messages(user: 'Hello from prompt 2!')
        end
      end

      server.register_prompts(test_prompt_class1, test_prompt_class2)

      prompts = server.instance_variable_get(:@prompts)
      expect(prompts['test_prompt_1']).to eq(test_prompt_class1)
      expect(prompts['test_prompt_2']).to eq(test_prompt_class2)
      expect(test_prompt_class1.server).to eq(server)
      expect(test_prompt_class2.server).to eq(server)
    end
  end

  describe '#handle_request' do
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

        expect(server).to receive(:send_result).with({}, 1)
        server.handle_request(request)
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

        expect(server).to receive(:send_result).with({
                                                       protocolVersion: FastMcp::Server::PROTOCOL_VERSION,
                                                       capabilities: server.capabilities,
                                                       serverInfo: {
                                                         name: server.name,
                                                         version: server.version
                                                       }
                                                     }, 1)
        server.handle_request(request)
      end
    end

    context 'with a tools/list request' do
      it 'responds with a list of tools' do
        request = { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json

        expect(server).to receive(:send_result) do |result, id|
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

        server.handle_request(request)
      end
      
      context 'with tool annotations' do
        let(:annotated_tool_class) do
          Class.new(FastMcp::Tool) do
            def self.name
              'annotated-tool'
            end

            def self.description
              'A tool with annotations'
            end
            
            annotations(
              title: 'Web Search Tool',
              read_only_hint: true,
              open_world_hint: true
            )

            def call(**_args)
              'Searching...'
            end
          end
        end
        
        before do
          server.register_tool(annotated_tool_class)
        end
        
        it 'includes annotations in the tools list' do
          request = { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json

          expect(server).to receive(:send_result) do |result, id|
            expect(id).to eq(1)
            
            annotated_tool = result[:tools].find { |t| t[:name] == 'annotated-tool' }
            expect(annotated_tool[:annotations]).to eq({
              title: 'Web Search Tool',
              readOnlyHint: true,
              openWorldHint: true
            })
          end

          server.handle_request(request)
        end
      end
      
      context 'with tool without annotations' do
        it 'does not include annotations field' do
          request = { jsonrpc: '2.0', method: 'tools/list', id: 1 }.to_json

          expect(server).to receive(:send_result) do |result, id|
            expect(id).to eq(1)
            
            test_tool = result[:tools].find { |t| t[:name] == 'test-tool' }
            expect(test_tool).not_to have_key(:annotations)
          end

          server.handle_request(request)
        end
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
          { content: [{ text: 'Hello, World!', type: 'text' }], isError: false },
          1,
          metadata: {}
        )
        server.handle_request(request)
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
          { content: [{ text: 'John Doe', type: 'text' }], isError: false },
          1,
          metadata: {}
        )
        server.handle_request(request)
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

        expect(server).to receive(:send_error).with(-32_602, 'Tool not found: non-existent-tool', 1)
        server.handle_request(request)
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

        expect(server).to receive(:send_error).with(-32_602, 'Invalid params: missing tool name', 1)
        server.handle_request(request)
      end
    end

    context 'with an invalid request' do
      it 'returns an error for an unknown method' do
        request = { jsonrpc: '2.0', method: 'unknown', id: 1 }.to_json

        expect(server).to receive(:send_error).with(-32_601, 'Method not found: unknown', 1)
        server.handle_request(request)
      end

      it 'returns an error for an invalid JSON-RPC request' do
        request = { id: 1 }.to_json

        expect(server).to receive(:send_error).with(-32_600, 'Invalid Request', 1)
        server.handle_request(request)
      end

      it 'returns an error for an invalid JSON request' do
        request = 'invalid json'

        expect(server).to receive(:send_error).with(-32_600, 'Invalid Request', nil)
        server.handle_request(request)
      end
    end
  end

  describe '#register_resource' do
    it 'registers a resource with the server' do
      test_resource_class = Class.new(FastMcp::Resource) do
        def self.name
          'test-resource'
        end

        def self.description
          'A test resource'
        end

        def uri
          'file://test.txt'
        end

        def name
          'test.txt'
        end

        def mime_type
          'text/plain'
        end

        def content
          'Hello, World!'
        end
      end

      server.register_resource(test_resource_class)

      expect(server.instance_variable_get(:@resources)).to include(test_resource_class)
    end
  end

  describe '#notify_resource_updated' do
    let(:test_resource_class) do
      Class.new(FastMcp::Resource) do
        def self.name
          'test-resource'
        end

        def self.description
          'A test resource'
        end

        # Use the class method pattern for URI
        uri 'file://test.txt'
        resource_name 'test.txt'
        mime_type 'text/plain'

        def content
          'Hello, World!'
        end
      end
    end

    before do
      server.register_resource(test_resource_class)
      # Simulate client initialization
      server.instance_variable_set(:@client_initialized, true)
    end

    it 'finds resource by URI using array search, not hash lookup' do
      # Subscribe to the resource
      server.instance_variable_get(:@resource_subscriptions)['file://test.txt'] = true

      # Mock the transport's send_message method to verify it's called
      transport = double('transport')
      server.instance_variable_set(:@transport, transport)
      
      expect(transport).to receive(:send_message).with(hash_including(
        jsonrpc: '2.0',
        method: 'notifications/resources/updated',
        params: hash_including(
          uri: 'file://test.txt',
          name: 'test-resource',
          mimeType: 'text/plain'
        )
      ))

      # This should successfully find the resource using array.find, not hash lookup
      server.notify_resource_updated('file://test.txt')
    end

    it 'does not send notification if no one is subscribed to the resource' do
      # Don't subscribe to the resource
      transport = double('transport')
      server.instance_variable_set(:@transport, transport)
      
      expect(transport).not_to receive(:send_message)

      server.notify_resource_updated('file://test.txt')
    end

    it 'does not send notification if client is not initialized' do
      # Unset client initialization
      server.instance_variable_set(:@client_initialized, false)
      server.instance_variable_get(:@resource_subscriptions)['file://test.txt'] = true
      
      transport = double('transport')
      server.instance_variable_set(:@transport, transport)

      expect(transport).not_to receive(:send_message)

      server.notify_resource_updated('file://test.txt')
    end

    it 'handles non-existent resource URI gracefully' do
      # Subscribe to a different resource
      server.instance_variable_get(:@resource_subscriptions)['file://nonexistent.txt'] = true
      
      transport = double('transport')
      server.instance_variable_set(:@transport, transport)

      # Mock should not be called since resource doesn't exist
      expect(transport).not_to receive(:send_message)

      server.notify_resource_updated('file://nonexistent.txt')
    end
  end
end
