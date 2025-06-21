# frozen_string_literal: true

class SampleTool < ApplicationTool
  description 'Greet a user'

  # Optional: Add annotations to provide hints about the tool's behavior
  # annotations(
  #   title: 'User Greeting',
  #   read_only_hint: true,      # This tool only reads data
  #   open_world_hint: false     # This tool only accesses the local database
  # )

  arguments do
    required(:id).filled(:integer).description('ID of the user to greet')
    optional(:prefix).filled(:string).description('Prefix to add to the greeting')
  end

  def call(id:, prefix: 'Hey')
    user = User.find(id)

    "#{prefix} #{user.first_name} !"
  end
end
