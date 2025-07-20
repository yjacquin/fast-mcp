# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FastMcp::JSONSchemaCompiler do
  let(:compiler) { described_class }

  describe '#process' do
    context 'with simple schema' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:name).filled(:string).description('the name')
          required(:age).filled(:integer)
          required(:email).filled(:string)
          optional(:admin).maybe(:bool).hidden
        end
      end

      it 'generates correct JSON schema' do
        result = compiler.process(schema)

        expect(result[:type]).to eq('object')
        expect(result[:properties]).to include(
          name: {
            type: 'string',
            description: 'the name'
          },
          age: { type: 'number' },
          email: { type: 'string' }
        )
        expect(result[:properties]).not_to include(:admin)
        expect(result[:required]).to contain_exactly('name', 'age', 'email')
      end
    end

    context 'with optional fields' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:name).filled(:string)
          optional(:age).filled(:integer)
          optional(:email).filled(:string)
        end
      end

      it 'only includes required fields in required array' do
        result = compiler.process(schema)

        expect(result[:required]).to contain_exactly('name')
        expect(result[:properties]).to include(
          name: { type: 'string' },
          age: { type: 'number' },
          email: { type: 'string' }
        )
      end
    end

    context 'with nested schema' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:name).filled(:string)
          required(:metadata).hash do
            required(:address).filled(:string)
            required(:phone).filled(:string)
            optional(:secret).maybe(:string).hidden
          end
        end
      end

      it 'correctly processes nested properties' do
        result = compiler.process(schema)

        expect(result[:properties][:metadata][:type]).to eq('object')
        expect(result[:properties][:metadata][:properties]).to include(
          address: { type: 'string' },
          phone: { type: 'string' }
        )
        expect(result[:properties][:metadata][:required]).to contain_exactly('address', 'phone')
      end
    end

    context 'with array type' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:tags).array(:string)
        end
      end

      it 'correctly processes array type' do
        result = compiler.process(schema)

        expect(result[:properties][:tags][:type]).to eq('array')
        expect(result[:properties][:tags][:items]).to eq({type: 'string'})
      end
    end

    context 'with validation constraints' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:username).filled(:string, min_size?: 3, max_size?: 20)
          required(:age).filled(:integer, gt?: 18, lt?: 100)
          required(:email).filled(:string, format?: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
        end
      end

      it 'includes validation constraints in schema' do
        result = compiler.process(schema)

        expect(result[:properties][:username][:minLength]).to eq(3)
        expect(result[:properties][:username][:maxLength]).to eq(20)
        expect(result[:properties][:age][:exclusiveMinimum]).to eq(18)
        expect(result[:properties][:age][:exclusiveMaximum]).to eq(100)
        # Email format test might need adjustment based on implementation
      end
    end

    context 'with enum values' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:status).filled(:string, included_in?: %w[pending active inactive])
        end
      end

      it 'includes enum values in schema' do
        result = compiler.process(schema)

        expect(result[:properties][:status][:enum]).to contain_exactly('pending', 'active', 'inactive')
      end
    end

    context 'with complex nested schema' do
      let(:schema) do
        Dry::Schema.JSON do
          required(:user).hash do
            required(:name).filled(:string)
            required(:address).hash do
              required(:street).filled(:string)
              required(:city).filled(:string)
              optional(:zip).filled(:string)
            end
            optional(:tags).array(:string)
          end
          optional(:metadata).hash do
            required(:created_at).filled(:string, format?: :date_time)
            optional(:updated_at).filled(:string, format?: :date_time)
          end
        end
      end

      it 'correctly processes complex nested schema' do
        result = compiler.process(schema)

        # Check user object
        expect(result[:properties][:user][:type]).to eq('object')
        expect(result[:properties][:user][:required]).to contain_exactly('name', 'address')

        # Check address nested object
        expect(result[:properties][:user][:properties][:address][:type]).to eq('object')
        expect(result[:properties][:user][:properties][:address][:required]).to contain_exactly('street', 'city')
        expect(result[:properties][:user][:properties][:address][:properties]).to include(
          street: { type: 'string' },
          city: { type: 'string' },
          zip: { type: 'string' }
        )

        # Check metadata object
        expect(result[:properties][:metadata][:type]).to eq('object')
        expect(result[:properties][:metadata][:required]).to contain_exactly('created_at')
        expect(result[:properties][:metadata][:properties][:created_at][:format]).to eq('date-time')
      end
    end
  end

  describe 'compatibility with MCP tool specification' do
    let(:example_tool_schema) do
      Dry::Schema.JSON do
        required(:location).filled(:string)
        optional(:units).filled(:string, included_in?: %w[metric imperial])
      end
    end

    it 'generates schema compatible with MCP tool specification' do
      result = compiler.process(example_tool_schema)

      # This should match the format expected by MCP
      expected_format = {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        type: 'object',
        properties: {
          location: { type: 'string' },
          units: {
            type: 'string',
            enum: %w[metric imperial]
          }
        },
        required: ['location']
      }

      expect(result).to match(expected_format)
    end
  end
end
