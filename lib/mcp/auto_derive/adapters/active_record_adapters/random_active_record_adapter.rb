# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      module ActiveRecordAdapters
        class RandomActiveRecordAdapter < FastMcp::AutoDerive::AutoDeriveAdapter
          def self.create_tool
            subclass = create_subclass(**subclass_params)

            define_call_method(subclass)

            configure_as_fast_mcp_tool(subclass)

            subclass
          end

          def self.configure_as_fast_mcp_tool(subclass)
            class_name = 'RandomActiveRecordModel'
            FastMcp::AutoDerive::Tools.const_set(class_name, subclass)
            full_class_name = 'MCPRandomActiveRecordModel'
            Object.const_set(full_class_name, subclass) unless Object.const_defined?(full_class_name)
            cursor_style_name = 'ToolsRandomActiveRecordModel'
            Object.const_set(cursor_style_name, subclass) unless Object.const_defined?(cursor_style_name)
          end

          def self.define_call_method(klass)
            klass.define_method(:call) do |params|
              params = params.transform_keys(&:to_sym)
              model_name = params[:model_name]

              raise "Required parameter 'model_name' not provided" if model_name.blank?

              begin
                model_class = model_name.constantize
                unless model_class.ancestors.include?(ActiveRecord::Base)
                  raise "Class '#{model_name}' is not an ActiveRecord model"
                end

                records = model_class.order('RANDOM()').limit(5)
                serialize_result(records)
              rescue NameError => e
                raise "Model '#{model_name}' not found: #{e.message}"
              end
            end
          end

          def self.subclass_params
            {
              name: 'random_active_record_model',
              class_name: 'ActiveRecord',
              method_name: :random,
              description: 'Get 5 random records from any model',
              parameters: {
                model_name: {
                  type: :string,
                  description: "The model name (e.g., 'Company', 'Person', 'Valuation')",
                  required: true
                }
              },
              finder_key: nil,
              post_process: nil,
              title: 'Get 5 random records from any model',
              annotations: {
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
              }
            }
          end
        end
      end
    end
  end
end
