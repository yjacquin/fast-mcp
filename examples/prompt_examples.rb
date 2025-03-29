# frozen_string_literal: true

require 'fast_mcp'

# Create an MCP server with prompt capability
server = MCP::Server.new(name: 'prompt-examples', version: '1.0.0')

# Create some example prompts
code_review_prompt = MCP::Prompt.new(
  name: 'code_review',
  description: 'Review code for issues and improvements',
  messages: [
    {
      role: 'user',
      content: {
        type: 'text',
        text: "Please review this code for issues, bugs, and potential improvements:\n\n```{{language}}\n{{code}}\n```"
      }
    }
  ],
  arguments: [
    {
      name: 'code',
      description: 'The code to review',
      required: true
    },
    {
      name: 'language',
      description: 'The programming language',
      required: true
    }
  ]
)

summarize_prompt = MCP::Prompt.new(
  name: 'summarize',
  description: 'Summarize a text into bullet points',
  messages: [
    {
      role: 'user',
      content: {
        type: 'text',
        text: "Please summarize the following text into {{number_of_points}} concise bullet points:\n\n{{text}}"
      }
    }
  ],
  arguments: [
    {
      name: 'text',
      description: 'The text to summarize',
      required: true
    },
    {
      name: 'number_of_points',
      description: 'Number of bullet points to generate',
      required: false
    }
  ]
)

multi_modal_prompt = MCP::Prompt.new(
  name: 'image_caption',
  description: 'Caption an image with a specific tone',
  messages: [
    {
      role: 'user',
      content: {
        type: 'text',
        text: "Please generate a {{tone}} caption for this image:"
      }
    },
    {
      role: 'user',
      content: {
        type: 'image',
        data: "BASE64_IMAGE_DATA_PLACEHOLDER",
        mimeType: "image/jpeg"
      }
    }
  ],
  arguments: [
    {
      name: 'tone',
      description: 'The tone of the caption (e.g., funny, serious, poetic)',
      required: true
    }
  ]
)

# Register the prompts with the server
server.register_prompts(code_review_prompt, summarize_prompt, multi_modal_prompt)

# Define some tools
class AskQuestionsAboutCodeTool < MCP::Tool
  description 'Ask questions about code to better understand it'
  
  arguments do
    required(:code).filled(:string).description('The code to analyze')
    required(:language).filled(:string).description('The programming language')
    required(:questions).array(:string).description('List of questions about the code')
  end
  
  def call(code:, language:, questions:)
    # In a real implementation, this would use the prompt system
    # and might involve an AI model to answer the questions
    "Analyzing #{language} code with #{questions.length} questions..."
  end
end

# Register tools
server.register_tool(AskQuestionsAboutCodeTool)

# Start the server
server.start