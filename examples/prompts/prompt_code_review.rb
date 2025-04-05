# frozen_string_literal: true

require_relative '../../lib/fast_mcp'

module FastMcp
  module Prompts
    # Example prompt for code review
    class CodeReviewPrompt < FastMcp::Prompt
      prompt_name 'code_review'
      description 'Asks the LLM to analyze code quality and suggest improvements'
      
      arguments do
        required(:code).description('Code to analyze')
        optional(:programming_language).description('Language the code is written in')
      end

      def call(code:, programming_language: nil)
        assistant_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_assistant.erb'))
        user_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_user.erb'))

        messages(
          assistant: ERB.new(assistant_template).result(binding),
          user: ERB.new(user_template).result(binding)
        )
      end
    end
  end
end
