# frozen_string_literal: true

require 'rails/generators/base'

module FastMcp
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Creates a FastMcp initializer for Rails applications'

      def copy_initializer
        template 'fast_mcp_initializer.rb', 'config/initializers/fast_mcp.rb'
      end

      def create_directories
        empty_directory 'app/tools'
        empty_directory 'app/resources'
        empty_directory 'app/prompts'
      end

      def copy_application_tool
        template 'application_tool.rb', 'app/tools/application_tool.rb'
      end

      def copy_application_resource
        template 'application_resource.rb', 'app/resources/application_resource.rb'
      end

      def copy_sample_tool
        template 'sample_tool.rb', 'app/tools/sample_tool.rb'
      end

      def copy_sample_resource
        template 'sample_resource.rb', 'app/resources/sample_resource.rb'
      end

      def copy_application_prompt
        template 'application_prompt.rb', 'app/prompts/application_prompt.rb'
      end

      def copy_sample_prompt
        template 'sample_prompt.rb', 'app/prompts/sample_prompt.rb'
      end

      def display_post_install_message
        say "\n========================================================="
        say 'FastMcp was successfully installed! 🎉'
        say "=========================================================\n"
        say 'You can now create:'
        say '  • Tools in app/tools/'
        say '  • Resources in app/resources/'
        say '  • Prompts in app/prompts/'
        say "\n"
        say 'Check config/initializers/fast_mcp.rb to configure the middleware.'
        say "=========================================================\n"
      end
    end
  end
end
