class Captain::Copilot::ActionRegistry
  DEFAULT_ACTIONS = [
    Captain::Copilot::Actions::AddLabel,
    Captain::Copilot::Actions::PrivateNote,
    Captain::Copilot::Actions::Assignment
  ].freeze

  def self.all = (@all ||= DEFAULT_ACTIONS.dup)

  def self.register(action_class)
    raise ArgumentError, 'Action class must implement the proposal action interface' unless
      %i[action_name schema].all? { |method| action_class.respond_to?(method) }

    all << action_class unless all.include?(action_class)
  end

  def self.unregister(action_class)
    all.delete(action_class) unless DEFAULT_ACTIONS.include?(action_class)
  end

  def self.fetch(name)
    all.find { |action| action.action_name == name.to_s } || raise(ArgumentError, 'Unsupported action')
  end
end
