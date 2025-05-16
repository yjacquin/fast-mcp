# frozen_string_literal: true

module FastMcp
  module AutoDerive
    class BaseAdapter < FastMcp::Tool
      def self.method_name
        raise NotImplementedError, 'Subclasses must define method_name'
      end

      def self.class_name
        raise NotImplementedError, 'Subclasses must define class_name'
      end

      def self.description
        raise NotImplementedError, 'Subclasses must define description'
      end

      def self.parameters
        {}
      end

      def self.read_only?
        true
      end

      def self.finder_key
        :id
      end

      def self.post_process(result, _params)
        result
      end

      def self.title
        nil
      end

      def self.destructive?
        !read_only?
      end

      def self.idempotent?
        false
      end

      def self.open_world?
        true
      end

      def self.annotations
        {
          title: title,
          readOnlyHint: read_only?,
          destructiveHint: destructive?,
          idempotentHint: idempotent?,
          openWorldHint: open_world?
        }.compact
      end

      def self.to_tool_definition
        schema = input_schema_to_json

        tool_def = {
          name: tool_name,
          description: description,
          inputSchema: schema
        }

        annots = annotations
        tool_def[:annotations] = annots unless annots.empty?

        tool_def
      end

      def call(params)
        raise NotImplementedError, 'Subclasses must implement the call method'
      end

      def format_error(error)
        { isError: true, content: [{ type: 'text', text: error[:message] }] }
      end

      # StandardError is handled in server.rb, but we can handle specific errors here
      def handle_errors
        yield
      rescue ActiveRecord::RecordNotFound => e
        format_error({ message: "record not found - #{e.message}" })
      rescue ActiveRecord::RecordInvalid => e
        format_error({ message: "invalid record - #{e.message}" })
      rescue ActionController::ParameterMissing => e
        format_error({ message: "missing parameter - #{e.message}" })
      end

      def self.create_subclass(name:, class_name:, method_name:, description:, parameters: {}, finder_key: :id, post_process: nil, title: nil, annotations: {})
        Class.new(self) do
          define_singleton_method(:name) { name }
          define_singleton_method(:tool_name) { name }
          define_singleton_method(:class_name) { class_name }
          define_singleton_method(:method_name) { method_name }
          define_singleton_method(:description) { description }
          define_singleton_method(:parameters) { parameters }
          define_singleton_method(:read_only?) { annotations.key?(:readOnlyHint) ? annotations[:readOnlyHint] : true }
          define_singleton_method(:finder_key) { finder_key }

          define_singleton_method(:title) { title }
          define_singleton_method(:destructive?) do
            annotations[:destructiveHint].nil? ? !read_only? : annotations[:destructiveHint]
          end
          define_singleton_method(:idempotent?) do
            annotations[:idempotentHint].nil? ? idempotent : annotations[:idempotentHint]
          end
          define_singleton_method(:open_world?) do
            annotations[:openWorldHint].nil? ? open_world : annotations[:openWorldHint]
          end

          arguments do
            if finder_key && !parameters.key?(finder_key.to_sym) && !parameters.key?(finder_key.to_s)
              required(finder_key).filled(:string,
                                          format?: /\A[0-9]+\z/).description("The #{finder_key} to find the #{class_name} record")
            end

            parameters.each do |param_name, param_details|
              param_type = (param_details[:type] || :string).to_sym
              is_optional = param_details[:optional] == true || param_details[:required] == false
              param_description = param_details[:description] || "#{param_name} parameter"

              if is_optional
                key = optional(param_name)
                if param_type == :int?
                  key.maybe(:integer).description(param_description)
                else
                  key.maybe(param_type).description(param_description)
                end
              else
                required(param_name).filled(param_type).description(param_description)
              end
            end
          end

          if post_process
            define_singleton_method(:post_process) do |result, params|
              post_process.call(result, params)
            end
          end
        end
      end

      # makes RSpec instance doubles work
      def serialize_result(result)
        if defined?(RSpec) && result.instance_variable_defined?(:@double_name) &&
           result.instance_variable_get(:@double_name) == 'ActiveRecord::Base' && result.respond_to?(:as_json)
          return result.as_json
        end

        case result
        when ActiveRecord::Base
          result.as_json
        when ActiveRecord::Relation
          result.map(&:as_json)
        when Array
          if result.all? { |item| item.is_a?(ActiveRecord::Base) }
            result.map(&:as_json)
          else
            result
          end
        else
          result
        end
      end
    end
  end
end
