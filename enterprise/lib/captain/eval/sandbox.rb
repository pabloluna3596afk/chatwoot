class Captain::Eval::Sandbox
  attr_reader :account, :inbox

  def prepare(pilot:)
    @account = Account.find_or_create_by!(name: 'Captain Eval') { |record| record.locale = 'es' }
    account.update!(plan: nil, plan_started_at: nil)
    account.enable_features!('captain_integration', 'captain_integration_v2')
    pilot ? account.enable_features!('captain_pilot') : account.disable_features!('captain_pilot')
    account.conversations.find_each(&:destroy!)
    prepare_inbox
    self
  end

  def prepare_inbox
    @inbox = account.inboxes.find_or_initialize_by(name: 'Captain Eval API')
    inbox.channel ||= Channel::Api.create!(account: account)
    inbox.assign_attributes(working_hours_enabled: false, out_of_office_message: nil, enable_auto_assignment: false)
    inbox.channel.update!(webhook_url: nil)
    inbox.save!
    raise 'La bandeja de evaluación debe ser API y no tener Captain conectado' unless inbox.api? && !CaptainInbox.exists?(inbox_id: inbox.id)
  end

  def assistant_for(vertical)
    attributes = vertical.fetch('assistant')
    assistant = Captain::Assistant.find_or_initialize_by(account: account, name: attributes.fetch('name'))
    assistant.update!(description: attributes.fetch('description'), response_guidelines: attributes.fetch('guidelines'),
                      guardrails: attributes.fetch('guardrails'))
    load_knowledge(assistant, vertical.fetch('knowledge'))
    assistant.reload
  end

  def load_knowledge(assistant, knowledge)
    Captain::AssistantResponse.where(assistant_id: assistant.id).delete_all
    embedding_service = Captain::Llm::EmbeddingService.new(account_id: account.id)
    knowledge.each do |pair|
      response = Captain::AssistantResponse.new(assistant: assistant, question: pair.fetch('question'), answer: pair.fetch('answer'),
                                                status: :approved)
      response.validate!
      response.embedding = embedding_service.get_embedding("#{response.question}: #{response.answer}")
      # Insert a validated record with its vector in one write: after_commit would enqueue another embedding call.
      Captain::AssistantResponse.insert_all!([response.attributes.except('id', 'created_at', 'updated_at')]) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def conversation_for(case_id)
    contact = account.contacts.find_or_create_by!(identifier: "captain-eval-#{case_id}") { |record| record.name = 'Cliente de prueba' }
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) { |record| record.source_id = SecureRandom.uuid }
    account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)
  end

  def add_message(conversation, content:, sender:, message_type:)
    message = conversation.messages.build(account: account, inbox: inbox, content: content, sender: sender, message_type: message_type)
    message.validate!
    # History only: bypass message delivery hooks, including automatic Captain responses.
    Message.insert_all!([message.attributes.except('id', 'created_at', 'updated_at')]) # rubocop:disable Rails/SkipsModelValidations
  end
end
