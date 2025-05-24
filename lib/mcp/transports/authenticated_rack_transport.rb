# frozen_string_literal: true

require_relative 'rack_transport'

module FastMcp
  module Transports
    class AuthenticatedRackTransport < RackTransport
      def initialize(app, server, options = {})
        super

        @auth_token = options[:auth_token]
        @auth_header_name = options[:auth_header_name] || 'Authorization'
        @auth_exempt_paths = options[:auth_exempt_paths] || []
        @auth_enabled = !@auth_token.nil?
      end

      def handle_mcp_request(request, env)
        if auth_enabled? && !exempt_from_auth?(request.path)
          auth_header = request.env["HTTP_#{@auth_header_name.upcase.gsub('-', '_')}"]
          token = auth_header&.gsub('Bearer ', '')
          auth_results = auth_check(token, request, env)
          return auth_results if auth_results
        end

        super(request, env)
      end

      private

      def auth_enabled?
        @auth_enabled
      end

      def exempt_from_auth?(path)
        @auth_exempt_paths.any? { |exempt_path| path.start_with?(exempt_path) }
      end

      # Override this method to implement custom authentication logic.
      # Store auth data in env
      def auth_check(token, request, env)
        valid_token?(token) ? nil : unauthorized_response(request, 'Unauthorized: Invalid or missing authentication token')
      end

      def valid_token?(token)
        token == @auth_token
      end

      def unauthorized_response(request, message = 'Unauthorized')
        @logger.error("Unauthorized request: #{message}")
        body = JSON.generate(
          {
            jsonrpc: '2.0',
            error: {
              code: -32_000,
              message: message
            },
            id: extract_request_id(request)
          }
        )

        [401, { 'Content-Type' => 'application/json' }, [body]]
      end

      def extract_request_id(request)
        return nil unless request.post?

        begin
          body = request.body.read
          request.body.rewind
          JSON.parse(body)['id']
        rescue StandardError
          nil
        end
      end
    end
  end
end
