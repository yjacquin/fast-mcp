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
  - [MessageBuilder API](#messagebuilder-api)
  - [Multiple Messages with Same Role](#multiple-messages-with-same-role)
- [Using Templates](#using-templates)
  - [ERB Templates](#erb-templates)
  - [Inline Templates](#inline-templates)
- [Advanced Prompt Features](#advanced-prompt-features)
  - [Message Content Types](#message-content-types)
  - [Dynamic Content](#dynamic-content)
  - [Prompt Filtering](#prompt-filtering)
  - [Prompt Annotations](#prompt-annotations)
  - [Authorization](#authorization)
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
class SimpleExamplePrompt < FastMcp::Prompt
  # prompt_name is auto-generated as 'simple_example' from the class name
  description 'A simple example prompt'
  
  def self.call(**_args)
    new.messages(
      assistant: "I'm an AI assistant. How can I help you?",
      user: "Tell me about Ruby."
    )
  end
end
```

When defining a prompt class, you can:

- Set a name using the `prompt_name` class method (optional - auto-generated from class name if not specified)
- Set a description using the `description` class method
- Define arguments using the `arguments` class method with Dry::Schema
- Implement the message creation in the `self.call` class method

> **Important**: The `call` method should be defined as a class method (`self.call`) that creates a new instance and calls the `messages` method on it. This is the standard pattern for FastMCP prompts.

#### Automatic Naming

If you don't specify a `prompt_name`, FastMCP will automatically generate one from your class name:
- The class name is converted to snake_case
- Any "Prompt" suffix is removed
- For example: `CodeReviewPrompt` → `code_review`, `DataAnalysisPrompt` → `data_analysis`

```ruby
class CodeReviewPrompt < FastMcp::Prompt
  # No need to specify prompt_name - it will be "code_review"
  description 'Reviews code for best practices'
end

class CustomNamePrompt < FastMcp::Prompt
  prompt_name 'my_custom_name'  # Override auto-naming when needed
  description 'Uses a custom name instead of auto-generated'
end
```

### Prompt Arguments

To define arguments for a prompt, use the `arguments` class method with a block using Dry::Schema syntax:

```ruby
class QueryPrompt < FastMcp::Prompt
  prompt_name 'query_example'
  description 'A prompt for answering user queries'
  
  arguments do
    required(:query).filled(:string)
    optional(:context).filled(:string)
  end
  
  def self.call(query:, context: nil)
    new.messages(
      assistant: "I'll help answer your question.",
      user: context ? "Question: #{query}\nContext: #{context}" : "Question: #{query}"
    )
  end
end
```

The `arguments` method works similarly to tools, allowing you to define:

- Required arguments using the `required` method
- Optional arguments using the `optional` method
- Types and validations for each argument

> **Note**: Unlike tools, prompts currently don't support the `.description()` method on schema fields. If you need to document your arguments, use comments in your code or add them to the prompt's main description.

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
def self.call(query:)
  new.messages(
    assistant: "I'll help you with your question.",
    user: "My question is: #{query}"
  )
end
```

This creates an array of messages with the specified roles and content. Note that only `user` and `assistant` roles are supported by the MCP specification.

### Array Format API

You can also use an array of message hashes with `:role` and `:content` keys:

```ruby
def self.call(query:)
  new.messages([
    { role: 'assistant', content: "I'll help you with your question." },
    { role: 'user', content: "My question is: #{query}" }
  ])
end
```

This format is particularly useful when you need to maintain a specific order of messages.

### MessageBuilder API

For more complex message construction, you can use the MessageBuilder class directly:

```ruby
def self.call(query:, examples: [])
  new.messages do
    assistant "I'll help you with your question."
    
    # Add example messages if provided
    examples.each do |example|
      user "Example: #{example}"
    end
    
    # Add the main query
    user "My question is: #{query}"
  end
end
```

The MessageBuilder provides a fluent API with these methods:
- `user(content)` - Add a user message
- `assistant(content)` - Add an assistant message
- `add_message(role:, content:)` - Add a message with a specific role

### Multiple Messages with Same Role

Both the array format and MessageBuilder support multiple messages with the same role:

```ruby
# Using array format
def self.call(query:, examples: [])
  message_array = [
    { role: 'assistant', content: "I'll help you with your question." }
  ]
  
  # Add example messages if provided
  examples.each do |example|
    message_array << { role: 'user', content: "Example: #{example}" }
  end
  
  # Add the main query
  message_array << { role: 'user', content: "My question is: #{query}" }
  
  new.messages(message_array)
end

# Using MessageBuilder
def self.call(query:, examples: [])
  new.messages do
    assistant "I'll help you with your question."
    
    # Add multiple user messages
    examples.each do |example|
      user "Example: #{example}"
    end
    
    user "My question is: #{query}"
  end
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
    required(:code).filled(:string)
    optional(:language).filled(:string)
  end
  
  def self.call(code:, language: nil)
    assistant_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_assistant.erb'))
    user_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_user.erb'))
    
    new.messages(
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
    required(:endpoint).filled(:string)
    required(:method).filled(:string)
    optional(:params).hash
  end
  
  def self.call(endpoint:, method:, params: {})
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
    
    new.messages(
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
    required(:document_type).filled(:string)
    required(:elements).array
    optional(:attributes).hash
  end
  
  def self.call(document_type:, elements:, attributes: {})
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
    
    new.messages(
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
    required(:query).filled(:string)
    optional(:context).filled(:string)
  end

  def self.call(query:, context: nil)
    # Create assistant message
    assistant_message = "I'll help you answer your question about: #{query}"
    
    # Create user message
    user_message = if context
                     "My question is: #{query}\nHere's some additional context: #{context}"
                   else
                     "My question is: #{query}"
                   end

    new.messages(
      assistant: assistant_message,
      user: user_message
    )
  end
end
```

## Advanced Prompt Features

### Message Content Types

Fast MCP supports different content types for messages. You can create content objects using the built-in helper methods:

#### Text Content

```ruby
class TextPrompt < FastMcp::Prompt
  def self.call(message:)
    prompt = new
    text_content = prompt.text_content(message)
    prompt.messages([
      { role: 'user', content: text_content }
    ])
  end
end
```

#### Image Content

```ruby
class ImagePrompt < FastMcp::Prompt
  def self.call(base64_data:, mime_type: 'image/png')
    prompt = new
    image_content = prompt.image_content(base64_data, mime_type)
    prompt.messages([
      { role: 'user', content: image_content }
    ])
  end
end
```

#### Resource Content

```ruby
class ResourcePrompt < FastMcp::Prompt
  def self.call(uri:, mime_type:, text: nil, blob: nil)
    prompt = new
    resource_content = prompt.resource_content(uri, mime_type, text: text, blob: blob)
    prompt.messages([
      { role: 'user', content: resource_content }
    ])
  end
end
```

#### Content Helper Methods

The following helper methods are available for creating properly formatted content:

- `text_content(text)` - Creates text content with type 'text'
- `image_content(data, mime_type)` - Creates image content with base64 data and MIME type
- `resource_content(uri, mime_type, text: nil, blob: nil)` - Creates resource content
- `content_from(content)` - Automatically detects and creates appropriate content type

#### Content Validation

All content is automatically validated to ensure it meets MCP specification requirements:

- Text content must have a `:text` field
- Image content must have `:data` (valid base64) and `:mimeType` fields
- Resource content must have `:uri`, `:mimeType`, and either `:text` or `:blob` fields

Remember that only "user" and "assistant" are valid roles according to the MCP specification.

### Dynamic Content

You can create prompts with dynamic content based on application state:

```ruby
class WeatherPrompt < FastMcp::Prompt
  prompt_name 'weather_forecast'
  description 'A prompt for weather forecasts'
  
  arguments do
    required(:location).filled(:string)
    optional(:days).filled(:integer)
  end
  
  def self.call(location:, days: 3)
    # Fetch weather data (example)
    weather_data = WeatherService.forecast(location, days)
    
    # Create a detailed context
    weather_context = weather_data.map do |day|
      "#{day[:date]}: #{day[:condition]}, High: #{day[:high]}°C, Low: #{day[:low]}°C"
    end.join("\n")
    
    new.messages(
      assistant: "I'll provide a weather forecast for #{location}.",
      user: "What's the weather forecast for #{location} for the next #{days} days?",
      assistant: "Here's the raw weather data:\n#{weather_context}",
      user: "Can you summarize this forecast in a friendly way?"
    )
  end
end
```

### Individual Message Creation

For more control over message creation, you can use the `message` method to create individual messages:

```ruby
class CustomMessagePrompt < FastMcp::Prompt
  def self.call(text:)
    prompt = new
    
    # Create individual messages
    intro_message = prompt.message(
      role: 'assistant',
      content: prompt.text_content("I'll help you with that.")
    )
    
    user_message = prompt.message(
      role: 'user',
      content: prompt.text_content(text)
    )
    
    [intro_message, user_message]
  end
end
```

### Prompt Filtering

Filter prompts dynamically based on request context:

```ruby
server.filter_prompts do |request, prompts|
  # Filter by user permissions, tags, etc.
  prompts.select { |p| p.authorized?(user: request.user) }
end
```

This allows you to control which prompts are available to clients based on the current request context, user permissions, or other criteria.

### Prompt Annotations

Add metadata to prompts:

```ruby
class ReviewPrompt < FastMcp::Prompt
  tags :code_review, :ai_assisted
  metadata :version, "2.0"
  annotations experimental: false
end
```

Annotations provide additional information about prompts that can be used by clients for better organization and presentation.

### Authorization

Control access to prompts:

```ruby
class SecurePrompt < FastMcp::Prompt
  prompt_name 'secure_prompt'
  description 'A prompt that requires authorization'
  
  arguments do
    required(:message).filled(:string)
  end
  
  # Authorization based on headers
  authorize { headers['role'] == 'admin' }
  
  # Authorization based on arguments
  authorize { |message:| message != 'forbidden' }
  
  def self.call(message:)
    new.messages(
      assistant: "This is a secure prompt.",
      user: message
    )
  end
end
```

Authorization blocks allow you to implement fine-grained access control for prompts, ensuring only authorized users can access sensitive or privileged prompt templates.

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
    required(:question).filled(:string)
  end
  
  def self.call(question:)
    new.messages(
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
    required(:topic).filled(:string)
    optional(:user_background).filled(:string)
  end
  
  def self.call(topic:, user_background: nil)
    new.messages do
      # First message - assistant introduction
      assistant "I'm going to help you understand #{topic}."
      
      # Second message - user background if provided
      if user_background
        user "My background: #{user_background}"
        # Third message - assistant acknowledgment
        assistant "I'll tailor my explanation based on your background."
      end
      
      # Final message - main user query
      user "Please explain #{topic} to me."
    end
  end
end
```

### Code Review Prompt with Templates

```ruby
class CodeReviewPrompt < FastMcp::Prompt
  prompt_name 'code_review'
  description 'A prompt for code review'
  
  arguments do
    required(:code).filled(:string)
    optional(:programming_language).filled(:string)
  end
  
  def self.call(code:, programming_language: nil)
    assistant_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_assistant.erb'))
    user_template = File.read(File.join(File.dirname(__FILE__), 'templates/code_review_user.erb'))
    
    new.messages(
      assistant: ERB.new(assistant_template).result(binding),
      user: ERB.new(user_template).result(binding)
    )
  end
end
```
