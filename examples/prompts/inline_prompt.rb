# frozen_string_literal: true

require_relative '../../lib/fast_mcp'

module FastMcp
  module Prompts
    # Example prompt that uses inline text instead of ERB templates
    class InlinePrompt < FastMcp::Prompt
      prompt_name 'inline_example'
      description 'An example prompt that uses inline text instead of ERB templates'
      
      arguments do
        required(:query).description('The user query to respond to')
        optional(:context).description('Additional context for the response')
      end

      def call(query:, context: nil)
        # Create assistant message
        assistant_message = "I'll help you answer your question about: #{query}"
        
        # Create user message
        user_message = if context
                         "My question is: #{query}\nHere's some additional context: #{context}"
                       else
                         "My question is: #{query}"
                       end

        # Using the messages method with a hash
        messages(
          assistant: assistant_message,
          user: user_message
        )
      end
    end
  end
end
