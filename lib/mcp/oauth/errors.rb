# frozen_string_literal: true

module FastMcp
  module OAuth
    class Error < StandardError
      def initialize(message = nil, error_type:, status: 400)
        @error_type = error_type
        @status = status

        super(message)
      end

      attr_reader :error_type, :status
    end

    class InvalidRequestError < Error
      def initialize(message = nil, status:)
        super(message, error_type: :invalid_request, status: status)
      end
    end

    class InvalidScopeError < Error
      def initialize(message = nil, required_scope:, status: 401)
        @required_scope = required_scope

        super(message, error_type: :invalid_scope, status: status)
      end

      attr_reader :required_scope
    end

    class ServerError < Error
      def initialize(message = nil, status: 500)
        super(message, error_type: :server_error, status: status)
      end
    end
  end
end
