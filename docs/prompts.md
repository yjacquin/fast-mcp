# Prompts

The Fast MCP implementation supports the MCP Prompts API, allowing servers to provide structured message templates for clients to use with language models.

## What are Prompts?

Prompts are pre-defined templates for interactions with language models. They include:

- A unique name for identification
- A description explaining the prompt's purpose
- A sequence of user and assistant messages that form the prompt
- Optional arguments that can be substituted into the prompt

## Creating Prompts

```ruby
require 'fast_mcp'

# Create a simple prompt with a single message
simple_prompt = MCP::Prompt.new(
  name: 'greeting',
  description: 'A friendly greeting',
  messages: [
    {
      role: 'user', 
      content: {
        type: 'text',
        text: 'Hello {{name}}, how can I help you with {{topic}} today?'
      }
    }
  ],
  arguments: [
    {
      name: 'name',
      description: 'The person to greet',
      required: true
    },
    {
      name: 'topic',
      description: 'The topic of interest',
      required: true
    }
  ]
)

# Create a more complex multi-turn prompt
code_review_prompt = MCP::Prompt.new(
  name: 'code_review',
  description: 'Review code for issues and suggest improvements',
  messages: [
    {
      role: 'user',
      content: {
        type: 'text',
        text: "Please review this {{language}} code for issues and suggest improvements:"
      }
    },
    {
      role: 'user',
      content: {
        type: 'text',
        text: "```{{language}}\n{{code}}\n```"
      }
    },
    {
      role: 'assistant',
      content: {
        type: 'text',
        text: "I'll review this {{language}} code carefully and provide feedback."
      }
    }
  ],
  arguments: [
    {
      name: 'language',
      description: 'The programming language',
      required: true
    },
    {
      name: 'code',
      description: 'The code to review',
      required: true
    }
  ]
)
```

## Registering Prompts with the Server

Once created, prompts need to be registered with an MCP Server:

```ruby
# Create a server
server = MCP::Server.new(name: 'my-server', version: '1.0.0')

# Register a single prompt
server.register_prompt(simple_prompt)

# Register multiple prompts at once
server.register_prompts(code_review_prompt, another_prompt)
```

## Supported Content Types

Prompts support several content types in messages:

### Text Content

The most common content type:

```ruby
{
  role: 'user',
  content: {
    type: 'text',
    text: 'This is a text message with {{variable}} placeholders.'
  }
}
```

### Image Content

For multimodal prompts:

```ruby
{
  role: 'user',
  content: {
    type: 'image',
    data: 'base64_encoded_image_data',
    mimeType: 'image/jpeg'
  }
}
```

### Resource References

Reference server-side resources:

```ruby
{
  role: 'user',
  content: {
    type: 'resource',
    resource: {
      uri: 'resource://documentation',
      mimeType: 'text/plain'
    }
  }
}
```

## Protocol Implementation

Fast MCP implements the following MCP endpoints for prompts:

- `prompts/list` - Lists all available prompts
- `prompts/get` - Retrieves a specific prompt with arguments

The server also sends a `notifications/prompts/list_changed` notification when the available prompts list changes.

## Example Usage

```ruby
require 'fast_mcp'

# Create a server
server = MCP::Server.new(name: 'prompt-server', version: '1.0.0')

# Create a prompt
summarize_prompt = MCP::Prompt.new(
  name: 'summarize',
  description: 'Summarize a text into key points',
  messages: [
    {
      role: 'user',
      content: {
        type: 'text',
        text: "Please summarize the following text into {{num_points}} key points:\n\n{{text}}"
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
      name: 'num_points',
      description: 'Number of key points to extract',
      required: false
    }
  ]
)

# Register the prompt
server.register_prompt(summarize_prompt)

# Start the server
server.start
```

See the [prompt_examples.rb](../examples/prompt_examples.rb) file for more detailed examples.