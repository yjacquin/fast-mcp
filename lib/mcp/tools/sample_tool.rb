# frozen_string_literal: true

module FastMcp
  module Tools
    # SampleTool provides a standalone tool for retrieving a sample of records from any model
    class SampleTool < FastMcp::Tool
      tool_name 'record_sample'
      description 'Get a sample of records from a model'

      arguments do
        required(:model_name).filled(:string).description('The model name to query records from')
        optional(:sample_size).maybe(:integer).description('Number of records to return (default: 5)')
      end

      def call(model_name:, sample_size: 5)
        # Ensure sample size is an integer with a reasonable default
        sample_size = sample_size.to_i.positive? ? sample_size.to_i : 5

        # Find the model class
        model_class = model_name.to_s.classify.constantize

        # Get the records with limit
        records = model_class.order('RANDOM()').limit(sample_size).to_a

        # Return serialized records
        serialize_records(records)
      rescue NameError => e
        { error: "Model not found: #{model_name}", details: e.message }
      rescue StandardError => e
        { error: 'Error fetching records', details: e.message }
      end

      private

      def serialize_records(records)
        records.map do |record|
          if record.respond_to?(:as_json)
            record.as_json
          else
            record.instance_variables.each_with_object({}) do |var, hash|
              hash[var.to_s.delete('@')] = record.instance_variable_get(var)
            end
          end
        end
      end
    end
  end
end
