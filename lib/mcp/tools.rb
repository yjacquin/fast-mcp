# frozen_string_literal: true

require_relative 'tools/sample_tool'

module FastMcp
  module Tools
    def self.register_all(server)
      # Don't automatically register any tools
      # server.register_tools(
      #   FastMcp::Tools::SampleTool
      # )
    end
  end
end
