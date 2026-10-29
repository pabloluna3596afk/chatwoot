class Captain::Copilot::AssistantResolver
  def initialize(account:, assistant_id: nil)
    @account = account
    @assistant_id = assistant_id
  end

  def perform
    return customer_assistants.find(@assistant_id) unless @assistant_id.nil?

    customer_assistants.ordered.first || internal_assistant
  end

  private

  attr_reader :account

  def customer_assistants
    account.captain_assistants
  end

  def internal_assistant
    account.with_lock do
      account.internal_captain_assistants.first_or_create! do |assistant|
        assistant.name = 'Copilot'
        assistant.description = 'Internal assistant for Copilot.'
        assistant.config = { 'internal' => true, 'product_name' => account.name }
      end
    end
  end
end
