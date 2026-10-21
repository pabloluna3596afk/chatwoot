class Variables::ContextFactory
  def self.timezone(account)
    account.reporting_timezone.presence || Time.zone.name
  end

  def self.for_message(message)
    conversation = message.conversation
    new(account: conversation.account, records: { conversation: conversation, inbox: message.inbox,
                                                  agent: message.sender || conversation.assignee }).build(surface: 'message')
  end

  def initialize(account:, records: {})
    @account = account
    @records = records
  end

  def build(surface:)
    values = {
      'account' => AccountDrop.new(@account), 'contact' => contact && ContactDrop.new(contact),
      'conversation' => @records[:conversation] && ConversationDrop.new(@records[:conversation]),
      'flow' => @records[:flow_run]&.then { |run| run.variables.merge('variables' => run.variables) },
      'inbox' => inbox && InboxDrop.new(inbox), 'agent' => UserDrop.new(agent), 'date' => DateDrop.new(timezone: self.class.timezone(@account))
    }
    values.slice(*Variables::Catalog::SURFACES.fetch(surface)).compact
  end

  private

  def contact
    @records[:contact] || @records[:conversation]&.contact
  end

  def inbox
    @records[:inbox] || @records[:conversation]&.inbox || @records[:campaign]&.inbox
  end

  def agent
    @records[:agent] || @records[:campaign]&.sender || @records[:conversation]&.assignee
  end
end

Variables::ContextFactory.prepend_mod_with('Variables::ContextFactory')
