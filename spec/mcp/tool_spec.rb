# frozen_string_literal: true

RSpec.describe FastMcp::Tool do
  describe '.tool_name' do
    it 'sets and returns the name' do
      test_class = Class.new(described_class)
      test_class.tool_name('custom_tool')

      expect(test_class.tool_name).to eq('custom_tool')
    end

    it 'sets and returns the name (exceeds 64 characters - will be truncated)' do
      test_class = Class.new(described_class)
      test_class.tool_name('custom_very_long_tool_name_that_exceeds_64_characters_that_will_be_truncated')

      expect(test_class.tool_name).to eq('custom_very_long_tool_name_that_exceeds_64_characters_that_will_')
    end

    it 'sets and returns the name (with special characters - special characters will be removed)' do
      test_class = Class.new(described_class)
      test_class.tool_name('custom_tool_name_with_special_characters_like!@#$%^&*()')

      expect(test_class.tool_name).to eq('custom_tool_name_with_special_characters_like')
    end

    it 'returns the current name when called with nil' do
      test_class = Class.new(described_class)
      test_class.tool_name('custom_tool')

      expect(test_class.tool_name(nil)).to eq('custom_tool')
    end

    it 'returns nil for anonymous classes when tool_name is not set' do
      test_class = Class.new(described_class)
      expect(test_class.tool_name).to be_nil
    end

    it 'returns the name of the class' do
      class Foo; class Bar < FastMcp::Tool; end; end

      expect(Foo::Bar.tool_name).to eq('FooBar')
    end
  end

  describe '.description' do
    it 'sets and returns the description' do
      test_class = Class.new(described_class)
      test_class.description('A test tool')

      expect(test_class.description).to eq('A test tool')
    end

    it 'returns the current description when called with nil' do
      test_class = Class.new(described_class)
      test_class.description('A test tool')

      expect(test_class.description(nil)).to eq('A test tool')
    end
  end

  describe '.arguments' do
    it 'sets up the input schema using Dry::Schema' do
      test_class = Class.new(described_class) do
        arguments do
          required(:name).filled(:string)
          required(:age).filled(:integer, gt?: 18)
        end
      end

      expect(test_class.input_schema).to be_a(Dry::Schema::JSON)
    end
  end

  describe '.authorize' do
    it 'records authorization blocks' do
      authorization_block_1 = Proc.new { true }
      authorization_block_2 = Proc.new { true }

      test_class = Class.new(described_class) do
        authorize(&authorization_block_1)
        authorize(&authorization_block_2)
      end

      expect(test_class.instance_variable_get('@authorization_blocks')).to be_an(Array)
      expect(test_class.instance_variable_get('@authorization_blocks').first).to be(authorization_block_1)
      expect(test_class.instance_variable_get('@authorization_blocks').last).to be(authorization_block_2)
    end
  end

  describe '.input_schema_to_json' do
    it 'returns nil when no input schema is defined' do
      test_class = Class.new(described_class)
      expect(test_class.input_schema_to_json).to be_nil
    end

    it 'converts the schema to JSON format using SchemaCompiler' do
      test_class = Class.new(described_class) do
        arguments do
          required(:name).filled(:string)
          required(:age).filled(:integer, gt?: 18)
        end
      end

      json_schema = test_class.input_schema_to_json
      expect(json_schema[:type]).to eq('object')
      expect(json_schema[:properties][:name][:type]).to eq('string')
      expect(json_schema[:properties][:age][:type]).to eq('number')
      expect(json_schema[:properties][:age][:exclusiveMinimum]).to eq(18)
      expect(json_schema[:required]).to include('name', 'age')
    end
  end

  describe '.call' do
    it 'raises NotImplementedError by default' do
      test_class = Class.new(described_class)
      expect { test_class.call }.to raise_error(NotImplementedError, 'Subclasses must implement the call method')
    end
  end

  describe '#call_with_schema_validation!' do
    let(:test_class) do
      Class.new(described_class) do
        arguments do
          required(:name).filled(:string)
          required(:age).filled(:integer, gt?: 18)
        end

        def call(**args)
          "Hello, #{args[:name]}! You are #{args[:age]} years old."
        end
      end
    end

    let(:instance) { test_class.new }

    it 'validates arguments against the schema and calls the method' do
      result = instance.call_with_schema_validation!(name: 'Test', age: 25)
      expect(result).to eq(['Hello, Test! You are 25 years old.', {}])
    end

    it 'raises InvalidArgumentsError when validation fails' do
      expect do
        instance.call_with_schema_validation!(name: 'Test', age: 15)
      end.to raise_error(FastMcp::Tool::InvalidArgumentsError)
    end

    context 'with metadata' do
      let(:test_class) do
        Class.new(described_class) do
          arguments do
            required(:name).filled(:string)
            required(:age).filled(:integer, gt?: 18)
          end

          def call(**args)
            _meta[:something] = "hey"

            "Hello, #{args[:name]}! You are #{args[:age]} years old."
          end
        end
      end

      it 'returns the modified metadata' do
        result = instance.call_with_schema_validation!(name: 'Test', age: 25)
        expect(result).to eq(['Hello, Test! You are 25 years old.', { something: 'hey' }])
      end
    end
  end

  describe '#headers' do
    let(:test_class) do
      Class.new(described_class) do
        def self.name
          'test-tool'
        end

        def self.description
          'A test tool'
        end

        def call(**_args)
          "Hello, #{headers['ENTITY']}!"
        end
      end
    end

    it 'can read headers' do
      tool = test_class.new(headers: { 'ENTITY' => 'World' })
      expect(tool.call).to eq('Hello, World!')
    end
  end

  describe '#authorized?' do
    context 'without authorization' do
      let(:open_tool_class) do
        Class.new(described_class) do
          def self.name
            'open-tool'
          end

          def self.description
            'An open tool'
          end

          def call(**_args)
            'Hello, World!'
          end
        end
      end

      it 'returns true' do
        tool = open_tool_class.new
        expect(tool.authorized?).to be true
      end
    end

    context 'with authorization' do
      context 'without arguments' do
        let(:token) { 'valid_token' }
        let(:authorized_tool_class) do
          valid_token = token
          Class.new(described_class) do
            def self.name
              'authorized-tool'
            end

            def self.description
              'An authorized tool'
            end

            authorize do
              headers['AUTHORIZATION'] == valid_token
            end

            def call(**_args)
              'Hello, Admin!'
            end
          end
        end

        it 'returns true when authorized' do
          tool = authorized_tool_class.new(headers: {
            'AUTHORIZATION' => token
          })

          expect(tool.authorized?).to be true
        end

        it 'returns false when not authorized' do
          tool = authorized_tool_class.new(headers: {
            'AUTHORIZATION' => 'invalid_token'
          })

          expect(tool.authorized?).to be false
        end
      end

      context 'with arguments' do
        let(:token) { 'valid_token' }
        let(:authorized_tool_class) do
          valid_token = token
          Class.new(described_class) do
            def self.name
              'authorized-tool'
            end

            def self.description
              'An authorized tool'
            end

            arguments do
              required(:name).filled(:string)
            end

            authorize do |args|
              headers['AUTHORIZATION'] == valid_token && args[:name] == 'admin'
            end

            def call(**_args)
              'Hello, Admin!'
            end
          end
        end

        it 'returns true when authorized' do
          tool = authorized_tool_class.new(headers: {
            'AUTHORIZATION' => token
          })

          expect(tool.authorized?(name: 'admin')).to be true
        end

        it 'returns false when not authorized' do
          tool = authorized_tool_class.new(headers: {
            'AUTHORIZATION' => token
          })

          expect(tool.authorized?(name: 'user')).to be false
        end
      end

      context 'with inherited authorization' do
        let(:token) { 'valid_token' }
        let(:root_authorized_tool_class) do
          valid_token = token
          Class.new(described_class) do
            def self.name
              'root-authorized-tool'
            end

            def self.description
              'A root authorized tool'
            end

            authorize do
              headers['AUTHORIZATION'] == valid_token
            end

            def call(**_args)
              'Hello, Admin!'
            end
          end
        end
        context 'with own authorization' do
          let(:child_authorized_tool_class) do
            Class.new(root_authorized_tool_class) do
              def self.name
                'child-authorized-tool'
              end

              def self.description
                'A child authorized tool'
              end

              authorize do
                headers['OTHER_HEADER'] == 'other_value'
              end

              def call(**_args)
                'Hello, Child Admin!'
              end
            end
          end

          it 'returns true when fully authorized' do
            tool = child_authorized_tool_class.new(headers: {
              'AUTHORIZATION' => token,
              'OTHER_HEADER' => 'other_value'
            })
            expect(tool.authorized?).to be true
          end

          it 'returns false when failing parent authorization' do
            tool = child_authorized_tool_class.new(headers: {
              'OTHER_HEADER' => 'other_value'
            })
            expect(tool.authorized?).to be false
          end

          it 'returns false when failing child authorization' do
            tool = child_authorized_tool_class.new(headers: {
              'AUTHORIZATION' => token
            })
            expect(tool.authorized?).to be false
          end
        end

        context 'without own authorization' do
          let(:child_tool_class) do
            Class.new(root_authorized_tool_class) do
              def self.name
                'child-tool'
              end

              def self.description
                'A child tool'
              end

              def call(**_args)
                'Hello, Child!'
              end
            end
          end

          it 'returns true when authorized' do
            tool = child_tool_class.new(headers: {
              'AUTHORIZATION' => token
            })
            expect(tool.authorized?).to be true
          end

          it 'returns false when not authorized' do
            tool = child_tool_class.new(headers: {
              'AUTHORIZATION' => 'invalid_token'
            })
            expect(tool.authorized?).to be false
          end
        end
      end

      context 'with composed authorization' do
        let(:current_user_module) do
          Module.new do
            def self.included(base)
              base.authorize do
                not current_user.nil?
              end
            end

            def current_user
              @current_user ||= headers['CURRENT_USER']
            end
          end
        end

        let(:token_module) do
          Module.new do
            def self.included(base)
              base.authorize do
                headers['AUTHORIZATION'] == 'valid_token'
              end
            end
          end
        end

        let(:composed_tool_class) do
          current_user_auth = current_user_module
          token_auth = token_module
          Class.new(described_class) do
            include current_user_auth
            include token_auth

            def self.name
              'composed-tool'
            end

            def self.description
              'A composed tool'
            end

            arguments do
              required(:name).filled(:string)
            end

            authorize do |name:|
              name.start_with?('Bob')
            end

            def call(**_args)
              "Hello, #{current_user}!"
            end
          end
        end

        it 'returns true when authorized by both modules' do
          tool = composed_tool_class.new(headers: {
            'AUTHORIZATION' => 'valid_token',
            'CURRENT_USER' => 'admin'
          })
          expect(tool.authorized?(name: "Bob")).to be true
        end

        it 'returns false when not authorized by one of the modules' do
          headers = [
            { 'AUTHORIZATION' => 'valid_token', 'CURRENT_USER' => nil },
            { 'AUTHORIZATION' => 'invalid_token', 'CURRENT_USER' => 'admin' },
          ]

          headers.each do |header|
            tool = composed_tool_class.new(headers: header)
            expect(tool.authorized?(name: "Bob")).to be false
          end
        end

        it 'returns false when not authorized by the tool' do
          tool = composed_tool_class.new(headers: {
            'AUTHORIZATION' => 'valid_token',
            'CURRENT_USER' => 'admin'
          })

          expect(tool.authorized?(name: "Alice")).to be false
        end
      end
    end
  end

  describe 'SchemaCompiler' do
    let(:compiler) { FastMcp::SchemaCompiler.new }

    describe '#process' do
      it 'converts a basic schema to JSON format' do
        schema = Dry::Schema.JSON do
          required(:name).filled(:string)
          required(:age).filled(:integer, gt?: 18)
        end

        result = compiler.process(schema)

        expect(result[:type]).to eq('object')
        expect(result[:properties][:name][:type]).to eq('string')
        expect(result[:properties][:age][:type]).to eq('number')
        expect(result[:properties][:age][:exclusiveMinimum]).to eq(18)
        expect(result[:required]).to include('name', 'age')
      end

      it 'handles optional fields' do
        schema = Dry::Schema.JSON do
          required(:name).filled(:string)
          optional(:email).filled(:string, format?: :email)
        end

        result = compiler.process(schema)

        expect(result[:required]).to include('name')
        expect(result[:required]).not_to include('email')
        expect(result[:properties][:email][:format]).to eq('email')
      end

      it 'handles nested objects' do
        schema = Dry::Schema.JSON do
          required(:person).hash do
            required(:first_name).filled(:string)
            required(:last_name).filled(:string)
          end
        end

        result = compiler.process(schema)

        expect(result[:properties][:person][:type]).to eq('object')
        expect(result[:properties][:person][:properties][:first_name][:type]).to eq('string')
        expect(result[:properties][:person][:properties][:last_name][:type]).to eq('string')
        expect(result[:properties][:person][:required]).to include('first_name', 'last_name')
      end

      it 'handles arrays' do
        schema = Dry::Schema.JSON do
          required(:tags).array(:string)
        end

        result = compiler.process(schema)

        expect(result[:properties][:tags][:type]).to eq('array')
      end

      it 'handles validation constraints' do
        schema = Dry::Schema.JSON do
          required(:username).filled(:string, min_size?: 3, max_size?: 20)
          required(:age).filled(:integer, gt?: 18, lt?: 100)
        end

        result = compiler.process(schema)

        expect(result[:properties][:username][:minLength]).to eq(3)
        expect(result[:properties][:username][:maxLength]).to eq(20)
        expect(result[:properties][:age][:exclusiveMinimum]).to eq(18)
        expect(result[:properties][:age][:exclusiveMaximum]).to eq(100)
      end

      it 'includes description field for properties' do
        schema = Dry::Schema.JSON do
          required(:name).filled(:string).description('User full name')
          required(:email).filled(:string, format?: :email).description('User email address')
        end

        result = compiler.process(schema)

        expect(result[:properties][:name][:description]).to eq('User full name')
        expect(result[:properties][:email][:description]).to eq('User email address')
      end

      it 'includes description field for nested properties' do
        schema = Dry::Schema.JSON do
          required(:person).hash do
            required(:first_name).filled(:string).description('First name of the person')
            required(:last_name).filled(:string).description('Last name of the person')
          end
        end

        result = compiler.process(schema)

        expect(result[:properties][:person][:properties][:first_name][:description]).to eq('First name of the person')
        expect(result[:properties][:person][:properties][:last_name][:description]).to eq('Last name of the person')
      end
    end
  end

  describe '.tags' do
    it 'sets and returns tags' do
      test_class = Class.new(described_class)
      test_class.tags :admin, :dangerous
      
      expect(test_class.tags).to eq([:admin, :dangerous])
    end
    
    it 'accepts array of tags' do
      test_class = Class.new(described_class)
      test_class.tags [:user, :safe]
      
      expect(test_class.tags).to eq([:user, :safe])
    end
    
    it 'returns empty array when no tags are set' do
      test_class = Class.new(described_class)
      
      expect(test_class.tags).to eq([])
    end
    
    it 'converts tags to symbols' do
      test_class = Class.new(described_class)
      test_class.tags 'admin', 'dangerous'
      
      expect(test_class.tags).to eq([:admin, :dangerous])
    end
  end
  
  describe '.metadata' do
    it 'sets and gets individual metadata values' do
      test_class = Class.new(described_class)
      test_class.metadata(:category, 'system')
      test_class.metadata(:risk_level, 'high')
      
      expect(test_class.metadata(:category)).to eq('system')
      expect(test_class.metadata(:risk_level)).to eq('high')
    end
    
    it 'returns all metadata when called without arguments' do
      test_class = Class.new(described_class)
      test_class.metadata(:category, 'system')
      test_class.metadata(:risk_level, 'high')
      
      expect(test_class.metadata).to eq({ category: 'system', risk_level: 'high' })
    end
    
    it 'returns empty hash when no metadata is set' do
      test_class = Class.new(described_class)
      
      expect(test_class.metadata).to eq({})
    end
    
    it 'returns nil for undefined metadata keys' do
      test_class = Class.new(described_class)
      
      expect(test_class.metadata(:undefined_key)).to be_nil
    end
  end

  describe '.annotations' do
    it 'sets and returns annotations hash' do
      test_class = Class.new(described_class)
      annotations = {
        title: 'Web Search',
        read_only_hint: true,
        open_world_hint: true
      }
      test_class.annotations(annotations)
      
      expect(test_class.annotations).to eq(annotations)
    end
    
    it 'returns empty hash when no annotations are set' do
      test_class = Class.new(described_class)
      
      expect(test_class.annotations).to eq({})
    end
    
    it 'returns the current annotations when called with nil' do
      test_class = Class.new(described_class)
      annotations = { title: 'Test Tool' }
      test_class.annotations(annotations)
      
      expect(test_class.annotations(nil)).to eq(annotations)
    end
    
    it 'supports all MCP annotation fields' do
      test_class = Class.new(described_class)
      annotations = {
        title: 'Delete File',
        read_only_hint: false,
        destructive_hint: true,
        idempotent_hint: true,
        open_world_hint: false
      }
      test_class.annotations(annotations)
      
      expect(test_class.annotations).to eq(annotations)
    end
  end
end
