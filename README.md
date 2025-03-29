# Fast MCP 🚀

<div align="center">
  <h3>Connect AI models to your Ruby applications with ease</h3>
  <p>No complex protocols, no integration headaches, no compatibility issues – just beautiful, expressive Ruby code.</p>
</div>

<p align="center">
  <a href="https://badge.fury.io/rb/fast-mcp"><img src="https://badge.fury.io/rb/fast-mcp.svg" alt="Gem Version" /></a>
  <a href="https://github.com/yjacquin/fast-mcp/workflows/CI/badge.svg"><img src="https://github.com/yjacquin/fast-mcp/workflows/CI/badge.svg" alt="CI Status" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
  <a href="code_of_conduct.md"><img src="https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg" alt="Contributor Covenant" /></a>
</p>

## 🌟 Interface your Servers with LLMs in minutes !

AI models are powerful, but they need to interact with your applications to be truly useful. Traditional approaches mean wrestling with:

- 🔄 Complex communication protocols and custom JSON formats
- 🔌 Integration challenges with different model providers
- 🧩 Compatibility issues between your app and AI tools
- 🧠 Managing the state between AI interactions and your data

Fast MCP solves all these problems by providing a clean, Ruby-focused implementation of the [Model Context Protocol](https://github.com/modelcontextprotocol), making AI integration a joy, not a chore.

## ✨ Features

- 🛠️ **Tools API** - Let AI models call your Ruby functions securely, with in-depth argument validation through [Dry-Schema](https://github.com/dry-rb/dry-schema).
- 📚 **Resources API** - Share data between your app and AI models
- 💬 **Prompts API** - Define structured prompt templates for LLM interactions
- 🔄 **Multiple Transports** - Choose from STDIO, HTTP, or SSE based on your needs
- 🧩 **Framework Integration** - Works seamlessly with Rails, Sinatra, and Hanami
- 🔒 **Authentication Support** - Secure your AI endpoints with ease
- 🚀 **Real-time Updates** - Subscribe to changes for interactive applications

## 💎 What Makes FastMCP Great

```ruby
# Define tools for AI models to use
server = MCP::Server.new(name: 'recipe-ai', version: '1.0.0')

# Define a tool by inheriting from MCP::Tool
class GetRecipesTool < MCP::Tool
  description "Find recipes based on ingredients"
  
    # These arguments will generate the needed JSON to be presented to the MCP Client
    # And they will be validated at run time.
    # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:ingredients).array(:string).description("List of ingredients")
    optional(:cuisine).filled(:string).description("Type of cuisine")
  end
  
  def call(ingredients:, cuisine: nil)
    Recipe.find_by_ingredients(ingredients, cuisine: cuisine)
  end
end

# Register the tool with the server
server.register_tool(GetRecipesTool)

# Share data resources with AI models by inheriting from MCP::Resource
class IngredientsResource < MCP::Resource
  uri "food/popular_ingredients"
  name "Popular Ingredients"
  mime_type "application/json"
  
  def default_content
    JSON.generate(Ingredient.popular.as_json)
  end
end

# Register the resource with the server
server.register_resource(IngredientsResource)

# Accessing the resource through the server
server.read_resource("food/popular_ingredients")

# Updating the resource content through the server
server.update_resource("food/popular_ingredients", JSON.generate({id: 1, name: 'tomato'}))


# Easily integrate with web frameworks
# config/application.rb (Rails)
config.middleware.use MCP::RackMiddleware.new(
  name: 'recipe-ai', 
  version: '1.0.0'
) do |server|
  # Register tools and resources here
  server.register_tool(GetRecipesTool)
end

# Secure your AI endpoints
config.middleware.use MCP::AuthenticatedRackMiddleware.new(
  name: 'recipe-ai',
  version: '1.0.0',
  token: ENV['MCP_AUTH_TOKEN']
)

# Build real-time applications
server.on_resource_update do |resource|
  ActionCable.server.broadcast("recipe_updates", resource.metadata)
end
```

## 📦 Installation

```ruby
# In your Gemfile
gem 'fast-mcp'

# Then run
bundle install

# Or install it yourself
gem install fast-mcp
```

## 🚀 Quick Start

### Create a Server with Tools and Resources

```ruby
require 'fast_mcp'

# Create an MCP server
server = MCP::Server.new(name: 'my-ai-server', version: '1.0.0')

# Define a tool by inheriting from MCP::Tool
class SummarizeTool < MCP::Tool
  description "Summarize a given text"
  
  arguments do
    required(:text).filled(:string).description("Text to summarize")
    optional(:max_length).filled(:integer).description("Maximum length of summary")
  end
  
  def call(text:, max_length: 100)
    # Your summarization logic here
    text.split('.').first(3).join('.') + '...'
  end
end

# Register the tool with the server
server.register_tool(SummarizeTool)

# Create a resource by inheriting from MCP::Resource
class StatisticsResource < MCP::Resource
  uri "data/statistics"
  name "Usage Statistics"
  description "Current system statistics"
  mime_type "application/json"
  
  def default_content
    JSON.generate({
      users_online: 120,
      queries_per_minute: 250,
      popular_topics: ["Ruby", "AI", "WebDev"]
    })
  end
end

# Register the resource with the server
server.register_resource(StatisticsResource.new)

# Start the server
server.start
```

### Integrate with Web Frameworks

#### Rails

```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    # ...
    config.middleware.use MCP::RackMiddleware.new(
      name: 'my-ai-server', 
      version: '1.0.0'
    ) do |server|
      # Register tools and resources here
      server.register_tool(SummarizeTool)
    end
  end
end
```

## 🧪 Testing with the inspector

MCP has developed a very [useful inspector](https://github.com/modelcontextprotocol/inspector).
You can use it to validate your implementation. I suggest you use the examples I provided with this project as an easy boilerplate.
Clone this project, then give it a go !

```shell
npx @modelcontextprotocol/inspector examples/server_with_stdio_transport.rb
```
Or to test with an SSE transport using a rack middleware:
```shell
npx @modelcontextprotocol/inspector examples/rack_middleware.rb
```

Or to test over SSE with an authenticated rack middleware:
```shell
npx @modelcontextprotocol/inspector examples/authenticated_rack_middleware.rb
```

You can test your custom implementation with the official MCP inspector by using:
```shell
# Test with a stdio transport:
npx @modelcontextprotocol/inspector path/to/your_ruby_file.rb

# Test with an HTTP / SSE server. In the UI select SSE and input your address.
npx @modelcontextprotocol/inspector
```

#### Sinatra

```ruby
# app.rb
require 'sinatra'
require 'fast_mcp'

use MCP::RackMiddleware.new(name: 'my-ai-server', version: '1.0.0') do |server|
  # Register tools and resources here
  server.register_tool(SummarizeTool)
end

get '/' do
  'Hello World!'
end
```

### Integrating with Claude Desktop

Add your server to your Claude Desktop configuration at:
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "my-great-server": {
      "command": "ruby",
      "args": [
        "/Users/path/to/your/awesome/fast-mcp/server.rb"
      ]
    }
  }
}
```

## 📊 Supported Specifications

| Feature | Status |
|---------|--------|
| ✅ **JSON-RPC 2.0** | Full implementation for communication |
| ✅ **Tool Definition & Calling** | Define and call tools with rich argument types |
| ✅ **Resource Management** | Create, read, update, and subscribe to resources |
| ✅ **Prompt Templates** | Define and share prompt templates with arguments |
| ✅ **Transport Options** | STDIO, HTTP, and SSE for flexible integration |
| ✅ **Framework Integration** | Rails, Sinatra, Hanami, and any Rack-compatible framework |
| ✅ **Authentication** | Secure your AI endpoints with token authentication |
| ✅ **Schema Support** | Full JSON Schema for tool arguments with validation |

## 🗺️ Use Cases

- 🤖 **AI-powered Applications**: Connect LLMs to your Ruby app's functionality
- 📊 **Real-time Dashboards**: Build dashboards with live AI-generated insights
- 🔗 **Microservice Communication**: Use MCP as a clean protocol between services
- 📚 **Interactive Documentation**: Create AI-enhanced API documentation
- 💬 **Chatbots and Assistants**: Build AI assistants with access to your app's data

## 📖 Documentation

- [🚀 Getting Started Guide](docs/getting_started.md)
- [🧩 Integration Guide](docs/integration_guide.md)
- [🛤️ Rails Integration](docs/rails_integration.md)
- [🌐 Sinatra Integration](docs/sinatra_integration.md)
- [🌸 Hanami Integration](docs/hanami_integration.md)
- [📚 Resources](docs/resources.md)
- [🛠️ Tools](docs/tools.md)
- [💬 Prompts](docs/prompts.md)
- [🔌 Transports](docs/transports.md)
- [📘 API Reference](docs/api_reference.md)

## 💻 Examples

Check out the [examples directory](examples) for more detailed examples:

- **🔨 Basic Examples**:
  - [Simple Server](examples/server_with_stdio_transport.rb)
  - [Tool Examples](examples/tool_examples.rb)
  - [Prompt Examples](examples/prompt_examples.rb)

- **🌐 Web Integration**:
  - [Rack Middleware](examples/rack_middleware.rb)
  - [Authenticated Endpoints](examples/authenticated_rack_middleware.rb)

## 🧪 Requirements

- Ruby 3.2+

## 👥 Contributing

We welcome contributions to Fast MCP! Here's how you can help:

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Please read our [Contributing Guide](CONTRIBUTING.md) for more details.

## 📄 License

This project is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🙏 Acknowledgments

- The [Model Context Protocol](https://github.com/modelcontextprotocol) team for creating the specification
- The [Dry-Schema](https://github.com/dry-rb/dry-schema) team for the argument validation.
- All contributors to this project
