# frozen_string_literal: true

class SamplePrompt < ApplicationPrompt
  # prompt_name is auto-generated as "sample" from class name
  description "A sample prompt to demonstrate functionality"
  
  # Define arguments using Dry::Schema syntax
  arguments do
    required(:input).filled(:string).description("The input to process")
    optional(:context).filled(:string).description("Additional context")
  end
  
  # Implement the call method to generate messages
  def call(input:, context: nil)
    # Build the user message
    user_message = "Process this input: #{input}"
    user_message += "\n\nAdditional context: #{context}" if context
    
    # Using the messages helper to create properly formatted messages
    messages(
      assistant: "I'm here to help you process your input.",
      user: user_message
    )
  end
end