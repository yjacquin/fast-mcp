# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      module ActiveRecordAdapters
        class CreateActiveRecordAdapter < FastMcp::AutoDerive::AutoDeriveAdapter
          def self.create_tool
            subclass = create_subclass(**subclass_params)

            define_call_method(subclass)

            configure_as_fast_mcp_tool(subclass)

            subclass
          end

          def self.configure_as_fast_mcp_tool(subclass)
            class_name = 'CreateActiveRecordModel'
            FastMcp::AutoDerive::Tools.const_set(class_name, subclass)
            full_class_name = 'MCPCreateActiveRecordModel'
            Object.const_set(full_class_name, subclass) unless Object.const_defined?(full_class_name)
            cursor_style_name = 'ToolsCreateActiveRecordModel'
            Object.const_set(cursor_style_name, subclass) unless Object.const_defined?(cursor_style_name)
          end

          def self.define_call_method(klass)
            klass.define_method(:call) do |params|
              params = params.transform_keys(&:to_sym)
              model_name = params[:model_name]
              attributes = params[:attributes]

              raise "Required parameter 'model_name' not provided" if model_name.blank?
              raise "Required parameter 'attributes' not provided" if attributes.blank?

              begin
                # Find the model class
                model_class = model_name.constantize
                unless model_class.ancestors.include?(ActiveRecord::Base)
                  raise "Class '#{model_name}' is not an ActiveRecord model"
                end

                # Parse attributes
                attributes_hash = JSON.parse(attributes)

                # Create record
                record = model_class.create(attributes_hash)
                serialize_result(record)
              rescue NameError => e
                raise "Model '#{model_name}' not found: #{e.message}"
              rescue JSON::ParserError => e
                raise "Invalid JSON in attributes: #{e.message}"
              rescue ActiveRecord::RecordInvalid => e
                raise "Validation failed: #{e.message}"
              end
            end
          end

          def self.subclass_params
            {
              name: 'create_active_record_model',
              class_name: 'ActiveRecord',
              method_name: :create,
              description: 'Create a new record for any model',
              parameters: {
                model_name: {
                  type: :string,
                  description: "The model name (e.g., 'Company', 'Person', 'Valuation')",
                  required: true
                },
                attributes: {
                  type: :string,
                  description: 'JSON string of attributes',
                  required: true
                }
              },
              finder_key: nil,
              post_process: nil,
              title: 'Create a new record for any model',
              annotations: {
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: true
              }
            }
          end
        end
      end
    end
  end
end
