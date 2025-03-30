class User < ApplicationRecord
  after_commit :notify_mcp

  private

  def notify_mcp
    Rails.logger.warn("Notifying MCP about user update")
    Rails.logger.warn("User.all.as_json: #{User.all.as_json}")
    Rails.logger.warn("SampleResource.uri: #{SampleResource.uri}")
    FastMcp.notify_resource_updated(SampleResource.uri)
  end
end
