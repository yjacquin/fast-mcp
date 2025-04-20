# Working with MCP Prompts

Prompts are a powerful feature in Fast MCP that allow you to define structured message templates for interacting with Large Language Models (LLMs). This guide covers everything you need to know about creating, using, and extending prompts in Fast MCP.

## Table of Contents

- [What are MCP Prompts?](#what-are-mcp-prompts)
- [Defining Prompts](#defining-prompts)
  - [Basic Prompt Definition](#basic-prompt-definition)
  - [Prompt Arguments](#prompt-arguments)
  - [Message Structure](#message-structure)
- [Creating Messages](#creating-messages)
  - [Hash Format API](#hash-format-api)
  - [Array Format API](#array-format-api)
  - [Multiple Messages with Same Role](#multiple-messages-with-same-role)
- [Using Templates](#using-templates)
  - [ERB Templates](#erb-templates)
  - [Inline Templates](#inline-templates)
- [Advanced Prompt Features](#advanced-prompt-features)
  - [Message Content Types](#message-content-types)
  - [Dynamic Content](#dynamic-content)
- [Best Practices](#best-practices)
- [Examples](#examples)

## What are MCP Prompts?

MCP Prompts are structured message templates that define how to interact with Large Language Models (LLMs). They provide a consistent way to:

- Define the structure of messages sent to LLMs
- Validate and process input arguments
- Create complex multi-message conversations
- Support different message roles (user, assistant)
- Include dynamic content based on input parameters

> **Note on Message Roles**: The MCP specification only supports "user" and "assistant" roles, unlike some LLM APIs (such as OpenAI) that also support a "system" role. If you need system-like instructions in your prompts, you'll need to include them as part of a user or assistant message.

Prompts are particularly useful for maintaining consistent interactions with LLMs across your application.

## Defining Prompts

### Basic Prompt Definition

To define a prompt, create a class that inherits from `FastMcp::Prompt`:

```ruby
class SimplePrompt < FastMcp::Prompt
  prompt_name 'simple_example'
  description 'A simple example prompt'
  
  def call(**_args)
    messages(
      assistant: "I'm an AI assistant. How can I help you?",
      user: "Tell me about Ruby."
    )
  end
end
```

When defining a prompt class, you can:

- Set a name using the `prompt_name` class method
- Set a description using the `description` class method
- Define arguments using the `arguments` class method with Dry::Schema
- Implement the message creation in the `call` instance method

### Prompt Arguments

To define arguments for a prompt, use the `arguments` class method with a block using Dry::Schema syntax:

```ruby
class QueryPrompt < FastMcp::Prompt
  prompt_name 'query_example'
  description 'A prompt for answering user queries'
  
  arguments do
    required(:query).filled(:string).description("The user's question")
    optional(:context).filled(:string).description("Additional context")
  end
  
  def call(query:, context: nil)
    messages(
      assistant: "I'll help answer your question.",
      user: context ? "Question: #{query}\nContext: #{context}" : "Question: #{query}"
    )
  end
end
```

The `arguments` method works the same way as in tools, allowing you to define:

- Required arguments using the `required` method
- Optional arguments using the `optional` method
- Types and validations for each argument
- Descriptions for each argument

### Message Structure

Messages in Fast MCP follow a specific structure that aligns with the MCP specification:

```ruby
{
  role: "user",  # or "assistant" (system role is not supported by MCP)
  content: {
    type: "text",
    text: "The actual message content"
  }
}
```

The `messages` method in the `Prompt` class handles creating this structure for you.

## Creating Messages

Fast MCP provides flexible ways to create messages through the `messages` method.

### Hash Format API

The traditional way to create messages is using a hash with roles as keys:

```ruby
def call(query:)
  messages(
    assistant: "I'll help you with your question.",
    user: "My question is: #{query}"
  )
end
```

This creates an array of messages with the specified roles and content. Note that only `user` and `assistant` roles are supported by the MCP specification.

### Array Format API

You can also use an array of hashes, each containing a single role-content pair:

```ruby
def call(query:)
  messages(
    { assistant: "I'll help you with your question." },
    { user: "My question is: #{query}" }
  )
end
```

This format is particularly useful when you need to maintain a specific order of messages.

### Multiple Messages with Same Role

One of the key advantages of the array format is the ability to have multiple messages with the same role:

```ruby
def call(query:, examples: [])
  message_array = [
    { assistant: "I'll help you with your question." }
  ]
  
  # Add example messages if provided
  examples.each do |example|
    message_array << { user: "Example: #{example}" }
  end
  
  # Add the main query
  message_array << { user: "My question is: #{query}" }
  
  messages(*message_array)
end
```

This allows for more complex conversation structures where you might need multiple consecutive messages from the same role.

## Using Templates

### ERB Templates

For more complex prompts, you can use ERB templates:

```ruby
class CodeReviewPrompt < FastMcp::Prompt
  prompt_name 'code_review'
  description 'A prompt for code review'
  
  arguments do
    required(:code).filled(:string).description("Code to review")
    optional(:language).filled(:string).description("Programming language")
  end
  
  def call(code:, language: nil)
    assistant_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_assistant.erb'))
    user_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_user.erb'))
    
    messages(
      assistant: ERB.new(assistant_template).result(binding),
      user: ERB.new(user_template).result(binding)
    )
  end
end
```

The ERB templates can access the arguments passed to the `call` method:

```erb
<!-- code_review_assistant.erb -->
I'll help you review your code. I'll analyze it for quality, best practices, and potential improvements.

<!-- code_review_user.erb -->
<% if language %>
Please review this <%= language %> code:
<%= code %>
<% else %>
Please review this code:
<%= code %>
<% end %>
```

#### JSON Templates with ERB

For structured data like JSON, ERB templates are particularly useful:

```ruby
class ApiPrompt < FastMcp::Prompt
  prompt_name 'api_request'
  description 'A prompt for generating API requests'
  
  arguments do
    required(:endpoint).filled(:string).description("API endpoint")
    required(:method).filled(:string).description("HTTP method")
    optional(:params).hash.description("Request parameters")
  end
  
  def call(endpoint:, method:, params: {})
    json_template = <<-ERB
{
  "request": {
    "endpoint": "<%= endpoint %>",
    "method": "<%= method %>",
    "parameters": <%= params.to_json %>
  },
  "instructions": "Please generate a valid API request for the above endpoint"
}
    ERB
    
    messages(
      assistant: "I'll help you generate an API request.",
      user: ERB.new(json_template).result(binding)
    )
  end
end
```

The embedded JSON template would render like this:

```json
{
  "request": {
    "endpoint": "https://api.example.com/users",
    "method": "POST",
    "parameters": {"name": "John Doe", "email": "john@example.com"}
  },
  "instructions": "Please generate a valid API request for the above endpoint"
}
```

#### XML Templates with ERB

Similarly, for XML-based content:

```ruby
class XmlPrompt < FastMcp::Prompt
  prompt_name 'xml_generator'
  description 'A prompt for generating XML documents'
  
  arguments do
    required(:document_type).filled(:string).description("Type of XML document")
    required(:elements).array.description("Elements to include")
    optional(:attributes).hash.description("Document attributes")
  end
  
  def call(document_type:, elements:, attributes: {})
    xml_template = <<-ERB
<?xml version="1.0" encoding="UTF-8"?>
<<%= document_type %><% attributes.each do |key, value| %> <%= key %>="<%= value %>"<% end %>>
<% elements.each do |element| %>
  <<%= element[:name] %>>
    <%= element[:content] %>
  </<%= element[:name] %>>
<% end %>
</<%= document_type %>>
    ERB
    
    messages(
      assistant: "I'll help you generate an XML document.",
      user: ERB.new(xml_template).result(binding)
    )
  end
end
```

The embedded XML template would render like this (with appropriate arguments):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<book isbn="978-3-16-148410-0" publisher="Example Publishing">
  <title>
    Ruby Programming
  </title>
  <author>
    Jane Smith
  </author>
  <year>
    2025
  </year>
</book>
```

### Inline Templates

For simpler cases, you can define templates inline:

```ruby
class InlinePrompt < FastMcp::Prompt
  prompt_name 'inline_example'
  description 'An example prompt that uses inline text'
  
  arguments do
    required(:query).filled(:string).description("The user query")
    optional(:context).filled(:string).description("Additional context")
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

    messages(
      assistant: assistant_message,
      user: user_message
    )
  end
end
```

## Advanced Prompt Features

### Message Content Types

Fast MCP supports different content types for messages:

```ruby
# Text content (default)
message(role: :user, content: text_content("Hello"))

# Image content
message(role: :user, content: image_content(image_data, "image/png"))

# Resource content
message(role: :user, content: resource_content(resource_id))
```

Remember that only "user" and "assistant" are valid roles according to the MCP specification.

### Dynamic Content

You can create prompts with dynamic content based on application state:

```ruby
class WeatherPrompt < FastMcp::Prompt
  prompt_name 'weather_forecast'
  description 'A prompt for weather forecasts'
  
  arguments do
    required(:location).filled(:string).description("Location for forecast")
    optional(:days).filled(:integer).description("Number of days")
  end
  
  def call(location:, days: 3)
    # Fetch weather data (example)
    weather_data = WeatherService.forecast(location, days)
    
    # Create a detailed context
    weather_context = weather_data.map do |day|
      "#{day[:date]}: #{day[:condition]}, High: #{day[:high]}°C, Low: #{day[:low]}°C"
    end.join("\n")
    
    messages(
      assistant: "I'll provide a weather forecast for #{location}.",
      user: "What's the weather forecast for #{location} for the next #{days} days?",
      assistant: "Here's the raw weather data:\n#{weather_context}",
      user: "Can you summarize this forecast in a friendly way?"
    )
  end
end
```

## Best Practices

When working with prompts:

1. **Keep prompts modular**: Create separate prompt classes for different tasks
2. **Use descriptive names**: Choose clear, descriptive names for your prompts
3. **Validate inputs**: Use the arguments schema to validate inputs
4. **Use templates for complex prompts**: Separate template files for better organization
5. **Consider message order**: The order of messages can significantly impact LLM responses
6. **Document your prompts**: Add clear descriptions to your prompts and arguments
7. **Test with different inputs**: Ensure your prompts work with various inputs
8. **System instructions as user messages**: Since the MCP specification doesn't support system roles, include system-like instructions as part of your first user or assistant message

## Examples

### Simple Question-Answer Prompt

```ruby
class QAPrompt < FastMcp::Prompt
  prompt_name 'qa_prompt'
  description 'A simple question-answer prompt'
  
  arguments do
    required(:question).filled(:string).description("The question to ask")
  end
  
  def call(question:)
    messages(
      assistant: "I'll answer your questions to the best of my ability.",
      user: question
    )
  end
end
```

### Multi-Message Conversation Prompt

```ruby
class ConversationPrompt < FastMcp::Prompt
  prompt_name 'conversation_prompt'
  description 'A multi-message conversation prompt'
  
  arguments do
    required(:topic).filled(:string).description("The topic to discuss")
    optional(:user_background).filled(:string).description("User background info")
  end
  
  def call(topic:, user_background: nil)
    message_array = []
    
    # First message - assistant introduction
    message_array << { assistant: "I'm going to help you understand #{topic}." }
    
    # Second message - user background if provided
    if user_background
      message_array << { user: "My background: #{user_background}" }
    end
    
    # Third message - assistant acknowledgment
    message_array << { assistant: "I'll tailor my explanation based on your background." }
    
    # Fourth message - main user query
    message_array << { user: "Please explain #{topic} to me." }
    
    messages(*message_array)
  end
end
```

### Code Review Prompt with Templates

```ruby
class CodeReviewPrompt < FastMcp::Prompt
  prompt_name 'code_review'
  description 'A prompt for code review'
  
  arguments do
    required(:code).filled(:string).description("Code to review")
    optional(:programming_language).filled(:string).description("Language the code is written in")
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
```
