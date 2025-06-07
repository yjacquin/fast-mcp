# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      module ActiveRecordAdapters
        class WhereActiveRecordAdapter < FastMcp::AutoDerive::AutoDeriveAdapter
          def self.create_tool
            subclass = create_subclass(**subclass_params)

            define_call_method(subclass)

            configure_as_fast_mcp_tool(subclass)

            subclass
          end

          def self.configure_as_fast_mcp_tool(subclass)
            class_name = 'WhereActiveRecordModel'
            FastMcp::AutoDerive::Tools.const_set(class_name, subclass)
            full_class_name = 'MCPWhereActiveRecordModel'
            Object.const_set(full_class_name, subclass) unless Object.const_defined?(full_class_name)
            cursor_style_name = 'ToolsWhereActiveRecordModel'
            Object.const_set(cursor_style_name, subclass) unless Object.const_defined?(cursor_style_name)
          end

          def self.define_call_method(klass)
            klass.define_method(:call) do |params|
              params = params.transform_keys(&:to_sym)
              model_name = params[:model_name]
              conditions = params[:conditions]

              raise "Required parameter 'model_name' not provided" if model_name.blank?
              raise "Required parameter 'conditions' not provided" if conditions.blank?

              begin
                model_class = model_name.to_s.constantize
                unless model_class.ancestors.include?(ActiveRecord::Base)
                  raise "Class '#{model_name}' is not an ActiveRecord model"
                end

                conditions_hash = conditions.is_a?(String) ? JSON.parse(conditions) : conditions

                if conditions_hash.empty?
                  raise 'Empty conditions are not allowed. Please provide at least one condition to filter records.'
                end

                records = model_class.where(conditions_hash)
                serialize_result(records)
              rescue NameError => e
                raise "Model '#{model_name}' not found: #{e.message}"
              rescue JSON::ParserError => e
                raise "Invalid JSON in conditions: #{e.message}"
              end
            end
          end

          def self.subclass_params
            {
              name: 'where_active_record_model',
              class_name: 'ActiveRecord',
              method_name: :where,
              description: 'Find records from any model matching conditions',
              parameters: {
                model_name: {
                  type: :string,
                  description: "The model name (e.g., 'Company', 'Person', 'Valuation')",
                  required: true
                },
                conditions: {
                  type: :string,
                  description: 'JSON string or object of conditions (empty conditions are not allowed)',
                  required: true
                }
              },
              finder_key: nil,
              post_process: nil,
              title: 'Find records from any model matching conditions',
              annotations: {
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
              }
            }
          end
        end
      end
    end
  end
end
