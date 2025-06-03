# frozen_string_literal: true

require 'logger'
require 'fileutils'
require_relative '../mcp/server'

# Create ActionTool and ActionResource modules when using Rails
if !defined?(ActionTool) && defined?(Rails)
  module ::ActionTool
    Base = FastMcp::Tool
  end
end

if !defined?(ActionResource) && defined?(Rails)
  module ::ActionResource
    Base = FastMcp::Resource
  end
end

module FastMcp
  # Railtie for integrating Fast MCP with Rails applications
  class Railtie < Rails::Railtie

    # Auto-register all tools and resources after the application is fully loaded
    config.after_initialize do |app|
      FastMcp::Railtie.eager_load_and_register_tools_and_resources
    end

    # Auto-register all tools and resources after the application is fully loaded
    config.to_prepare do
      FastMcp.server.clear_tools!
      FastMcp.server.clear_resources!

      FastMcp::Railtie.eager_load_and_register_tools_and_resources
    end

    def self.eager_load_and_register_tools_and_resources
      Rails.autoloaders.main.eager_load_dir(FastMcp.tools_dir)
      Rails.autoloaders.main.eager_load_dir(FastMcp.resources_dir)

      tools = ApplicationTool.descendants.sort_by(&:name)
      resources = ApplicationResource.descendants.sort_by(&:name)

      FastMcp.server.register_tools(*tools)
      FastMcp.server.register_resources(*resources, notify: false)
    end

    # Add rake tasks
    rake_tasks do
      # Path to the tasks directory in the gem
      path = File.expand_path('../tasks', __dir__)
      Dir.glob("#{path}/**/*.rake").each { |f| load f }
    end
  end
end
