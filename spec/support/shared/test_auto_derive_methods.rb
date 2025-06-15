module TestAutoDeriveMethods
  def self.extended(base)
    base.class_eval do
      class << self
        attr_accessor :mcp_exposed_methods

        def name
          'TestClass'
        end

        def underscore
          'test_class'
        end

        def expose_to_mcp(method_name, description:, parameters: {}, read_only: true, finder_key: :id, tool_name: nil,
                         title: nil, destructive: nil, idempotent: false, open_world: true)
          tool_name ||= "#{name}_#{method_name}"

          self.mcp_exposed_methods = mcp_exposed_methods.merge(
            tool_name => {
              method_name: method_name,
              description: description,
              parameters: parameters,
              read_only: read_only,
              finder_key: finder_key,
              class_name: name,
              title: title,
              destructive: destructive,
              idempotent: idempotent,
              open_world: open_world
            }
          )
        end
      end
    end
  end
end
