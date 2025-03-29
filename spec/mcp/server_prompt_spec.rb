# frozen_string_literal: true

RSpec.describe MCP::Server do
  let(:server) { described_class.new(name: 'test-server', version: '1.0.0') }
  let(:test_prompt) do
    MCP::Prompt.new(
      name: 'test_prompt',
      description: 'A test prompt',
      messages: [
        {
          role: 'user',
          content: {
            type: 'text',
            text: 'Hello {{name}}, how are you today?'
          }
        }
      ],
      arguments: [
        {
          name: 'name',
          description: 'The name to greet',
          required: true
        }
      ]
    )
  end

  describe 'prompts capabilities' do
    it 'includes prompts capabilities by default' do
      expect(server.capabilities[:prompts]).to include(listChanged: true)
    end
  end

  describe '#register_prompt' do
    it 'registers a prompt with the server' do
      server.register_prompt(test_prompt)
      expect(server.prompts['test_prompt']).to eq(test_prompt)
    end

    it 'logs the registration' do
      expect(server.logger).to receive(:info).with("Registered prompt: test_prompt")
      server.register_prompt(test_prompt)
    end
  end

  describe '#register_prompts' do
    let(:second_prompt) do
      MCP::Prompt.new(
        name: 'second_prompt',
        description: 'Another test prompt',
        messages: [{ role: 'user', content: { type: 'text', text: 'Example {{variable}}' } }],
        arguments: [{ name: 'variable', description: 'A variable', required: true }]
      )
    end

    it 'registers multiple prompts with the server' do
      server.register_prompts(test_prompt, second_prompt)
      expect(server.prompts['test_prompt']).to eq(test_prompt)
      expect(server.prompts['second_prompt']).to eq(second_prompt)
    end
  end

  describe '#remove_prompt' do
    before { server.register_prompt(test_prompt) }

    it 'removes a prompt from the server' do
      expect(server.remove_prompt('test_prompt')).to be true
      expect(server.prompts['test_prompt']).to be_nil
    end

    it 'returns false when prompt does not exist' do
      expect(server.remove_prompt('nonexistent')).to be false
    end

    it 'logs the removal' do
      expect(server.logger).to receive(:info).with("Removed prompt: test_prompt")
      server.remove_prompt('test_prompt')
    end
  end

  describe 'JSON-RPC request handling' do
    before { server.register_prompt(test_prompt) }

    describe 'prompts/list endpoint' do
      let(:request) do
        {
          jsonrpc: '2.0',
          id: 1,
          method: 'prompts/list',
          params: {}
        }.to_json
      end

      it 'handles prompts/list requests' do
        # Mock the transport to capture the response
        allow(server).to receive(:send_result) do |result, id|
          expect(id).to eq(1)
          expect(result[:prompts]).to be_an(Array)
          expect(result[:prompts].first[:name]).to eq('test_prompt')
        end

        server.handle_request(request)
      end
    end

    describe 'prompts/get endpoint' do
      let(:request) do
        {
          jsonrpc: '2.0',
          id: 2,
          method: 'prompts/get',
          params: {
            name: 'test_prompt',
            arguments: {
              name: 'John'
            }
          }
        }.to_json
      end

      it 'handles prompts/get requests' do
        # Mock the transport to capture the response
        allow(server).to receive(:send_result) do |result, id|
          expect(id).to eq(2)
          expect(result[:messages]).to be_an(Array)
          expect(result[:messages].first[:content][:text]).to include('Hello John')
        end

        server.handle_request(request)
      end

      it 'returns an error for nonexistent prompts' do
        bad_request = {
          jsonrpc: '2.0',
          id: 3,
          method: 'prompts/get',
          params: { name: 'nonexistent' }
        }.to_json

        expect(server).to receive(:send_error).with(-32_602, "Prompt not found: nonexistent", 3)
        server.handle_request(bad_request)
      end

      it 'returns an error when prompt name is missing' do
        bad_request = {
          jsonrpc: '2.0',
          id: 4,
          method: 'prompts/get',
          params: {}
        }.to_json

        expect(server).to receive(:send_error).with(-32_602, 'Invalid params: missing prompt name', 4)
        server.handle_request(bad_request)
      end
    end

    describe 'prompts/list_changed notification' do
      it 'sends notification when a prompt is registered' do
        # First initialize the client
        server.instance_variable_set(:@client_initialized, true)
        
        # Setup a mock transport
        transport = double('transport')
        allow(transport).to receive(:send_message)
        server.instance_variable_set(:@transport, transport)
        
        # Expect the notification to be sent
        expect(transport).to receive(:send_message).with(
          hash_including(method: 'notifications/prompts/list_changed')
        )
        
        # Register a new prompt
        server.register_prompt(
          MCP::Prompt.new(
            name: 'new_prompt',
            description: 'A new prompt',
            messages: [{ role: 'user', content: { type: 'text', text: 'Example' } }]
          )
        )
      end
    end
  end
end