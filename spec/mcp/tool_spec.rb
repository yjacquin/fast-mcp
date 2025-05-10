# frozen_string_literal: true

RSpec.describe FastMcp::Tool do
  describe '.tool_name' do
    it 'sets and returns the name' do
      test_class = Class.new(described_class)
      test_class.tool_name('custom_tool')

      expect(test_class.tool_name).to eq('custom_tool')
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
      class Bar < described_class; end;

      expect(Bar.tool_name).to eq('Bar')
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
end
