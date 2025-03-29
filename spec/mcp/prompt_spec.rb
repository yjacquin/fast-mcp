# frozen_string_literal: true

RSpec.describe MCP::Prompt do
  let(:prompt_name) { 'test_prompt' }
  let(:prompt_description) { 'A test prompt' }
  let(:prompt_messages) do
    [
      {
        role: 'user',
        content: {
          type: 'text',
          text: 'Hello {{name}}, how are you today? Tell me about {{topic}}.'
        }
      }
    ]
  end
  let(:prompt_arguments) do
    [
      {
        name: 'name',
        description: 'The name to greet',
        required: true
      },
      {
        name: 'topic',
        description: 'The topic to discuss',
        required: true
      }
    ]
  end

  subject(:prompt) do
    described_class.new(
      name: prompt_name,
      description: prompt_description,
      messages: prompt_messages,
      arguments: prompt_arguments
    )
  end

  describe '#initialize' do
    it 'sets the name' do
      expect(prompt.name).to eq(prompt_name)
    end

    it 'sets the description' do
      expect(prompt.description).to eq(prompt_description)
    end

    it 'sets the arguments' do
      expect(prompt.arguments).to eq(prompt_arguments)
    end
  end

  describe '#to_list_hash' do
    it 'returns a hash with name, description, and arguments' do
      hash = prompt.to_list_hash
      expect(hash[:name]).to eq(prompt_name)
      expect(hash[:description]).to eq(prompt_description)
      expect(hash[:arguments]).to be_an(Array)
      expect(hash[:arguments].length).to eq(2)
    end

    it 'formats arguments correctly' do
      hash = prompt.to_list_hash
      arg = hash[:arguments].first
      expect(arg[:name]).to eq('name')
      expect(arg[:description]).to eq('The name to greet')
      expect(arg[:required]).to be(true)
    end
  end

  describe '#get_content' do
    let(:arguments) do
      {
        'name' => 'John',
        'topic' => 'Ruby programming'
      }
    end

    it 'returns a hash with description and messages' do
      result = prompt.get_content(arguments)
      expect(result[:description]).to eq(prompt_description)
      expect(result[:messages]).to be_an(Array)
    end

    it 'interpolates arguments into message text' do
      result = prompt.get_content(arguments)
      message_text = result[:messages].first[:content][:text]
      expect(message_text).to include('Hello John')
      expect(message_text).to include('Ruby programming')
    end

    it 'handles missing arguments by leaving placeholders intact' do
      result = prompt.get_content({ 'name' => 'Jane' })
      message_text = result[:messages].first[:content][:text]
      expect(message_text).to include('Hello Jane')
      expect(message_text).to include('{{topic}}')
    end
  end

  context 'with more complex prompts' do
    let(:multi_message_prompt) do
      described_class.new(
        name: 'multi_message',
        description: 'A prompt with multiple messages',
        messages: [
          {
            role: 'user',
            content: {
              type: 'text',
              text: 'Analyze this {{language}} code:'
            }
          },
          {
            role: 'user',
            content: {
              type: 'text',
              text: "```{{language}}\n{{code}}\n```"
            }
          },
          {
            role: 'assistant',
            content: {
              type: 'text',
              text: 'I will analyze this {{language}} code for you.'
            }
          }
        ],
        arguments: [
          {
            name: 'language',
            description: 'Programming language',
            required: true
          },
          {
            name: 'code',
            description: 'Code to analyze',
            required: true
          }
        ]
      )
    end

    it 'processes all messages with the provided arguments' do
      code_with_newlines = "def hello\n  puts \"Hello, world!\"\nend"
      
      result = multi_message_prompt.get_content({
        'language' => 'Ruby',
        'code' => code_with_newlines
      })

      expect(result[:messages][0][:content][:text]).to eq('Analyze this Ruby code:')
      
      expected_code_block = "```Ruby\ndef hello\n  puts \"Hello, world!\"\nend\n```"
      expect(result[:messages][1][:content][:text]).to eq(expected_code_block)
      
      expect(result[:messages][2][:content][:text]).to eq('I will analyze this Ruby code for you.')
    end
  end

  context 'with non-text content types' do
    let(:mixed_content_prompt) do
      described_class.new(
        name: 'mixed_content',
        description: 'A prompt with mixed content types',
        messages: [
          {
            role: 'user',
            content: {
              type: 'text',
              text: 'Describe this {{object_type}}:'
            }
          },
          {
            role: 'user',
            content: {
              type: 'image',
              data: 'base64data',
              mimeType: 'image/jpeg'
            }
          }
        ],
        arguments: [
          {
            name: 'object_type',
            description: 'Type of object in the image',
            required: true
          }
        ]
      )
    end

    it 'only interpolates text content' do
      result = mixed_content_prompt.get_content({
        'object_type' => 'car'
      })

      expect(result[:messages][0][:content][:text]).to eq('Describe this car:')
      expect(result[:messages][1][:content][:type]).to eq('image')
      expect(result[:messages][1][:content][:data]).to eq('base64data')
    end
  end
end