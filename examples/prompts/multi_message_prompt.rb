# frozen_string_literal: true

require_relative '../../lib/fast_mcp'

module FastMcp
  module Prompts
    # Example prompt that demonstrates multiple messages in a specific order
    class MultiMessagePrompt < FastMcp::Prompt
      prompt_name 'multi_message_example'
      description 'An example prompt that uses multiple messages in a specific order'
      
      arguments do
        required(:topic).description('The topic to discuss')
        optional(:user_background).description('Background information about the user')
        optional(:additional_context).description('Any additional context for the conversation')
      end

      def call(topic:, user_background: nil, additional_context: nil)
        # Create an array to store our messages in the desired order
        message_array = []
        
        # First message - system context (represented as assistant)
        message_array << { assistant: "I'm going to help you understand #{topic}." }
        
        # Second message - user background if provided
        if user_background
          message_array << { user: "My background: #{user_background}" }
        end
        
        # Third message - assistant acknowledgment
        message_array << { assistant: "I'll tailor my explanation based on your background." }
        
        # Fourth message - main user query
        message_array << { user: "Please explain #{topic} to me." }
        
        # Fifth message - additional context if provided
        if additional_context
          message_array << { user: "Additional context: #{additional_context}" }
        end
        
        # Use the messages method with the array of message hashes
        messages(*message_array)
      end
    end
  end
end
