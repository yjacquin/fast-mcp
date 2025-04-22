# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      module ActiveRecordAdapters
        class UpdateActiveRecordAdapter < FastMcp::AutoDerive::AutoDeriveAdapter
          def self.create_tool
            subclass = create_subclass(**subclass_params)

            define_update_call_method(subclass)

            configure_as_fast_mcp_tool(subclass)

            subclass
          end

          def self.configure_as_fast_mcp_tool(subclass)
            class_name = 'UpdateActiveRecordModel'
            FastMcp::AutoDerive::Tools.const_set(class_name, subclass)
            full_class_name = 'MCPUpdateActiveRecordModel'
            Object.const_set(full_class_name, subclass) unless Object.const_defined?(full_class_name)
            cursor_style_name = 'ToolsUpdateActiveRecordModel'
            Object.const_set(cursor_style_name, subclass) unless Object.const_defined?(cursor_style_name)
          end

          def self.define_update_call_method(klass)
            klass.define_method(:call) do |params|
              params = params.transform_keys(&:to_sym)
              model_name = params[:model_name]
              id = params[:id]
              attributes = params[:attributes]

              raise "Required parameter 'model_name' not provided" if model_name.blank?
              raise "Required parameter 'id' not provided" if id.blank?
              raise "Required parameter 'attributes' not provided" if attributes.blank?

              begin
                model_class = model_name.constantize
                unless model_class.ancestors.include?(ActiveRecord::Base)
                  raise "Class '#{model_name}' is not an ActiveRecord model"
                end

                record = model_class.find(id)

                attributes_hash = JSON.parse(attributes)

                raise "Update failed: #{record.errors.full_messages.join(', ')}" unless record.update(attributes_hash)

                serialize_result(record)
              rescue NameError => e
                raise "Model '#{model_name}' not found: #{e.message}"
              rescue ActiveRecord::RecordNotFound => e
                raise "Record not found: #{e.message}"
              rescue JSON::ParserError => e
                raise "Invalid JSON in attributes: #{e.message}"
              end
            end
          end

          def self.subclass_params
            {
              name: 'update_active_record_model',
              class_name: 'ActiveRecord',
              method_name: :update,
              description: 'Update a record for any model',
              parameters: {
                model_name: {
                  type: :string,
                  description: "The model name (e.g., 'Company', 'Person', 'Valuation')",
                  required: true
                },
                id: {
                  type: :string,
                  description: 'The ID of the record to update',
                  required: true
                },
                attributes: {
                  type: :string,
                  description: 'JSON string of attributes to update',
                  required: true
                }
              },
              finder_key: nil,
              post_process: nil,
              title: 'Update a record for any model',
              annotations: {
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: true
              }
            }
          end
        end
      end
    end
  end
end
