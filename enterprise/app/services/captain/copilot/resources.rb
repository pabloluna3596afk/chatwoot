# The record types available to Copilot's read-only get_data tool.
module Captain::Copilot::Resources
  def self.all
    [Captain::Copilot::Resources::Conversations, Captain::Copilot::Resources::Contacts]
  end

  def self.build(name, account:, user:)
    resource = all.find { |candidate| name == candidate::NAME }
    raise ArgumentError, "Unknown resource #{name}. Available resources: #{all.map { |candidate| candidate::NAME }.join(', ')}" unless resource

    resource.new(account: account, user: user)
  end
end
