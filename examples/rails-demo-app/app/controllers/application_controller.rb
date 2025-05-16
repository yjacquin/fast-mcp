class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  expose_action_to_mcp :healthcheck, description: "Check the health of the database", read_only: true

  def healthcheck
    begin
      ActiveRecord::Base.connection.execute("SELECT 1 FROM sqlite_master LIMIT 1")
      render json: { status: "ok", message: "Database connection successful" }, status: :ok
    rescue => e
      render json: { status: "error", message: "Database connection failed: #{e.message}" }, status: :service_unavailable
    end
  end
end
