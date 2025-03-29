# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2025-03-29

### Fixed

- Fixed handling of notifications without IDs (e.g., notifications/initialized)
- Updated JSON-RPC message handling to properly process notification format
- Fixed transport layer to correctly handle nil responses for notifications
- Fixed issue with IO objects being accidentally printed in standard output
- Improved logger to safely handle IO objects in log messages
- Fixed StdIO transport to avoid returning unnecessary values
- Added missing `set_client_initialized` method to MCP::Logger class

## [0.2.0] - 2025-03-29

### Added

- Added Prompts API implementation (MCP::Prompt class)
- New JSON-RPC endpoints for prompts: prompts/list and prompts/get
- Server methods for registering and managing prompts
- Multi-modal support in prompts (text, image, audio, resource types)
- Updated documentation with prompts information
- Added example for using prompts (prompt_examples.rb)
- Comprehensive test suite for prompt functionality

## [0.1.0] - 2025-03-12

### Added

- Initial release of the Fast MCP library
- MCP::Tool class with multiple definition styles
- MCP::Server class with STDIO transport and HTTP / SSE transport
- Rack Integration with authenticated and standard middleware options
- Resource management with subscription capabilities
- Binary resource support
- Examples with STDIO Transport, HTTP & SSE, Rack app
- Initialize lifecycle with capabilities 
- Comprehensive test suite with RSpec
