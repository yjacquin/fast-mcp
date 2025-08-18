#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/fast_mcp'

# Example prompt demonstrating the enhanced messages helper
# with support for multiple same-role messages and array input
class FewShotTranslationPrompt < FastMcp::Prompt
  prompt_name "few_shot_translation"
  description "A few-shot learning prompt for translation tasks using array format"
  
  arguments do
    required(:word).filled(:string)
    optional(:target_language).filled(:string)
  end

  def call(word:, target_language: "Spanish")
    # Example using array format to support multiple same-role messages
    messages([
      { role: "user", content: "Translate 'hello' to #{target_language}" },
      { role: "assistant", content: "hola" },
      { role: "user", content: "Translate 'goodbye' to #{target_language}" },
      { role: "assistant", content: "adiós" },
      { role: "user", content: "Translate 'thank you' to #{target_language}" },
      { role: "assistant", content: "gracias" },
      { role: "user", content: "Translate '#{word}' to #{target_language}" }
    ])
  end
end

# Example using the builder pattern for complex conversation flows
class ConversationFlowPrompt < FastMcp::Prompt
  prompt_name "conversation_flow"
  description "Demonstrates builder pattern for complex conversation flows"
  
  arguments do
    required(:topic).filled(:string)
    optional(:expertise_level).filled(:string)
  end

  def call(topic:, expertise_level: "beginner")
    # Using builder pattern with block syntax
    messages do
      user "I'm interested in learning about #{topic}"
      assistant "That's great! What's your current level of knowledge about #{topic}?"
      user "I'm a #{expertise_level}"
      assistant "Perfect! Let me provide some #{expertise_level}-friendly information about #{topic}."
      
      # Add multiple follow-up user questions
      add_message(role: "user", content: "Can you give me some practical examples?")
      add_message(role: "user", content: "What are the most important concepts to understand first?")
      
      assistant "I'd be happy to provide examples and key concepts for #{topic}."
    end
  end
end

# Example maintaining backward compatibility with hash input
class BackwardCompatiblePrompt < FastMcp::Prompt
  prompt_name "backward_compatible"
  description "Shows that the original hash format still works"
  
  arguments do
    required(:code).filled(:string)
    optional(:language).filled(:string)
  end

  def call(code:, language: "code")
    # Original hash format still works
    messages(
      assistant: "I'll help you review your #{language}.",
      user: "Please review this #{language}: #{code}"
    )
  end
end

# Demonstration script
if __FILE__ == $0
  puts "=== Few-Shot Translation Prompt ==="
  
  few_shot = FewShotTranslationPrompt.new
  result = few_shot.call_with_schema_validation!(word: "computer", target_language: "French")
  
  puts "Generated #{result.size} messages:"
  result.each_with_index do |message, index|
    puts "#{index + 1}. #{message[:role]}: #{message[:content][:text]}"
  end
  
  puts "\n=== Conversation Flow Prompt ==="
  
  conversation = ConversationFlowPrompt.new
  result = conversation.call_with_schema_validation!(topic: "machine learning", expertise_level: "intermediate")
  
  puts "Generated #{result.size} messages:"
  result.each_with_index do |message, index|
    puts "#{index + 1}. #{message[:role]}: #{message[:content]}"
  end
  
  puts "\n=== Backward Compatible Prompt ==="
  
  compatible = BackwardCompatiblePrompt.new
  result = compatible.call_with_schema_validation!(code: "def hello; puts 'hi'; end", language: "Ruby")
  
  puts "Generated #{result.size} messages:"
  result.each_with_index do |message, index|
    puts "#{index + 1}. #{message[:role]}: #{message[:content][:text]}"
  end
end