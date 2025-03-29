#!/usr/bin/env ruby
# Markdown Server - A simple MCP server for saving markdown files from Claude
#
# Prerequisites:
#   - Ruby (any recent version)
#   - Bundler gem (gem install bundler)
#   The rest of dependencies will be installed automatically.
#
# Usage: ruby mcp_markdown_server.rb [options]
#   -d, --directory DIR     Directory to save markdown files (default: ./saved)
#   -l, --log FILE         Path to log file (default: ./logs/mcp-server.log)
#   -h, --help             Show help message
#
# Claude Desktop Setup:
# Add this to your Claude Desktop config file (~/.config/Claude/claude_desktop_config.json):
#
# {
#   "mcpServers": {
#     "markdown-saver": {
#       "name": "Markdown Saver",
#       "transport": "stdio",
#       "command": "/full-path-to/ruby",
#       "args": [
#         "/full-path-to/server-directory/mcp_markdown_server.rb",
#         "--directory",
#         "/full-path-to-output-directory/markdown",
#         "--log",
#         "/full-path-to/server-directory/logs/claude-run.log"
#       ],
#       "workingDirectory": "/full-path-to/server-directory"
#     }
#   }
# }
#
# Configuration:
#   MARKDOWN_SAVE_DIR - Directory where markdown files will be saved (default: ./saved)
#   MCP_LOG_FILE     - Path to log file (default: ./logs/mcp-server.log)
#
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "fast-mcp", "0.2.1", path: File.expand_path("../../", __FILE__)
  gem "rack" # looks like rack is running depency, even when we are using only stdio
end

require "fast_mcp"

# File Operations
require "fileutils"

# Parse command line arguments
require "optparse"
require "singleton"

class Config
  include Singleton

  attr_reader :save_dir

  def initialize
    @save_dir = ENV["MARKDOWN_SAVE_DIR"] || "./saved"
  end

  def save_dir=(dir)
    raise ArgumentError, "Directory path cannot be empty" if dir.nil? || dir.empty?
    @save_dir = File.expand_path(dir)
    FileUtils.mkdir_p(@save_dir) unless File.directory?(@save_dir)
  end
end

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-d", "--directory DIR", "Directory to save markdown files (default: ./saved)") do |dir|
    Config.instance.save_dir = dir
  end

  opts.on("-l", "--log FILE", String, "Path to log file (default: ./logs/mcp-server.log)") do |file|
    MCP::Logger.log_path = File.expand_path(file)
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

class SaveMarkdownTool < MCP::Tool
  description "Save markdown content to a specified file path on the server"

  arguments do
    required(:filename).filled(:string).description("Relative filename, e.g. notes.md")
    required(:content).filled(:string).description("Markdown content to save")
  end

  def config
    Config.instance
  end

  def call(filename:, content:)
    # Validate filename to prevent directory traversal
    if filename.include?("../") || filename.start_with?("/")
      raise "Invalid filename. Must be a relative path without directory traversal"
    end

    filepath = File.expand_path("#{config.save_dir}/#{filename}")

    FileUtils.mkdir_p(File.dirname(filepath))
    File.write(filepath, content)

    "✅ Markdown file saved to #{filepath}"
  rescue => e
    raise "❌ Error: #{e.message}"
  end
end



# Create and configure the MCP server
server = MCP::Server.new(
  name: "Markdown Saver Server",
  version: "0.1.0"
)

# Register our tool with the server
server.register_tool(SaveMarkdownTool)

# Start the server in stdio mode
begin
  server.start
rescue => e
  puts "Failed to start server: #{e.message}"
  exit 1
end
