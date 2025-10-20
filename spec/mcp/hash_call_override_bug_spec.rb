# frozen_string_literal: true

# This spec demonstrates a bug introduced by overriding Hash#call in Dry::Schema::Macros::Hash (lib/mcp/tool.rb)
# Without the adjusted monkey patch, this test fails with:
# ArgumentError: wrong number of arguments (given 1, expected 0)

RSpec.describe 'Hash#call override breaks reusable schema objects' do
  it 'validates a schema that references another schema object via hash()' do
    item_schema = Dry::Schema.JSON do
      required(:id).filled(:integer)
      required(:value).filled(:string)
    end

    main_schema = Dry::Schema.JSON do
      required(:data).hash do
        required(:items).value(:array).each { hash(item_schema) }
      end
    end

    input = {
      data: {
        items: [
          { id: 1, value: 'lorem ipsum' }
        ]
      }
    }

    result = main_schema.call(input)
    expect(result.success?).to be true
  end
end
