# frozen_string_literal: true

require 'logger'
require 'fileutils'
require_relative '../mcp/server'

# Create ActionTool and ActionResource modules at load time
unless defined?(ActionTool)
  module ::ActionTool
    Base = FastMcp::Tool
  end
end

unless defined?(ActionResource)
  module ::ActionResource
    Base = FastMcp::Resource
  end
end

module FastMcp
  # Railtie for integrating Fast MCP with Rails applications
  class Railtie < Rails::Railtie
    # Add tools and resources directories to autoload paths
    initializer 'fast_mcp.setup_autoload_paths' do |app|
      # Rails 7 compatible autoload paths setup
      if Rails.version >= '7.0'
        app.config.autoload_paths += %W[
          #{app.root}/app/tools
          #{app.root}/app/resources
        ]
      else
        # Fallback for older Rails versions
        app.config.autoload_paths += %W[
          #{app.root}/app/tools
          #{app.root}/app/resources
        ]
      end
    end

    # Auto-register all tools and resources after the application is fully loaded
    config.after_initialize do
      # Load all files in app/tools and app/resources directories
      Dir[Rails.root.join('app', 'tools', '**', '*.rb')].each { |f| require f }
      Dir[Rails.root.join('app', 'resources', '**', '*.rb')].each { |f| require f }
    end

    # Add rake tasks
    rake_tasks do
      # Path to the tasks directory in the gem
      path = File.expand_path('../tasks', __dir__)
      Dir.glob("#{path}/**/*.rake").each { |f| load f }
    end
  end
end
