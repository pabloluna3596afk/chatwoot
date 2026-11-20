# Fictional, isolated data. Inserts bypass delivery, AI, webhooks and automation callbacks.
class Seeders::CaptainDecisionsDemo
  MARKER = 'captain-decisions-demo-v1'.freeze
  NAME = 'Captain decisions demo (fictional)'.freeze
  CONTACT_NAME = 'Alex Rivera'.freeze
  SCENARIOS = [
    { name: 'reply', kind: 'reply', outcome: 'created', origin: 'model', trigger: 'customer_message',
      content: { en: 'We are open from 09:00 to 18:00', es: 'Atendemos de 09:00 a 18:00' },
      reason: { en: 'Answered the question about opening hours.', es: 'Respondió la pregunta sobre el horario de atención.' },
      technical: { model: 'demo-model', credits_consumed: 1, cost: 0.0004 } },
    { name: 'handoff', kind: 'handoff', outcome: 'completed', origin: 'model', trigger: 'tool', private: true,
      content: { en: 'The customer asked to speak to a person', es: 'El cliente pidió hablar con una persona' },
      reason: { en: 'The customer requested human assistance.', es: 'El cliente solicitó atención de una persona.' },
      attributes: { captain_handoff: { reason_category: 'customer_request', source: 'tool' } }, technical: {} },
    { name: 'evaluation', kind: 'resolve', outcome: 'completed', origin: 'model', trigger: 'evaluation', activity: true,
      content: {
        en: 'Captain resolved the conversation after an evaluation',
        es: 'Captain cerró la conversación después de una evaluación'
      },
      reason: { en: 'No pending questions were detected.', es: 'No se detectaron preguntas pendientes.' },
      evidence: { complete: true }, technical: { credits_consumed: 0 } },
    { name: 'silence', kind: 'close_unanswered', outcome: 'completed', origin: 'time', trigger: 'inactivity', activity: true,
      content: {
        en: 'Captain closed the conversation because the customer did not reply',
        es: 'Captain cerró la conversación porque el cliente no respondió'
      },
      reason: { en: 'The inactivity threshold was reached without a customer reply.', es: 'Se cumplió el tiempo de inactividad sin respuesta del cliente.' },
      technical: { credits_consumed: 0 } },
    { name: 'signal', kind: 'completion_review', outcome: 'confirmed', origin: 'model', trigger: 'completion_signal', activity: true,
      content: { en: 'Captain confirmed closure', es: 'Captain confirmó el cierre' },
      reason: { en: 'The review confirmed that no matters remained pending.', es: 'La revisión confirmó que no había asuntos pendientes.' },
      evidence: { probable_complete: true, expects_customer_reply: false }, technical: { credits_consumed: 0 } },
    { name: 'minimal', kind: 'reply', outcome: 'created', origin: 'model', trigger: 'customer_message',
      content: { en: 'Thank you', es: 'Gracias' }, reason: nil, technical: {} }
  ].freeze
  ACTIVITY_SCENARIOS = [
    {
      name: 'human_assignment',
      content: {
        en: 'Maria assigned this conversation to Alex Rivera',
        es: 'Maria asignó esta conversación a Alex Rivera'
      },
      names: { en: ['Maria', 'Alex Rivera'], es: ['Maria', 'Alex Rivera'] },
      source_type: 'User'
    },
    {
      name: 'team_assignment',
      content: {
        en: 'Maria assigned this conversation to the Support team',
        es: 'Maria asignó esta conversación al equipo de Soporte'
      },
      names: { en: ['Maria', 'Support'], es: ['Maria', 'Soporte'] },
      source_type: 'User'
    },
    {
      name: 'label_added',
      content: { en: 'Maria added the label priority', es: 'Maria añadió la etiqueta priority' },
      names: { en: %w[Maria priority], es: %w[Maria priority] },
      source_type: 'User'
    },
    {
      name: 'automation',
      content: {
        en: 'Automation marked this conversation as pending',
        es: 'La automatización marcó esta conversación como pendiente'
      },
      names: { en: ['Automation'], es: ['automatización'] },
      source_type: 'User',
      content_attributes: { messageSource: { type: 'automation', id: 31, name: 'Demo follow-up' } }
    }
  ].freeze

  def initialize(account:)
    @account = account
  end

  def perform!
    abort 'dev:captain_decisions_demo is disabled in production' if Rails.env.production?

    @account.with_lock do
      prepare_conversation
      SCENARIOS.each_with_index { |scenario, index| seed_scenario(scenario, index) }
      ACTIVITY_SCENARIOS.each_with_index { |scenario, index| seed_activity_scenario(scenario, index) }
      puts "Fictional demo: /app/accounts/#{@account.id}/conversations/#{@conversation.display_id}" # rubocop:disable Rails/Output -- local preview URL
    end
  end

  private

  def insert(model, attributes)
    model.find(model.insert!(attributes, returning: ['id']).rows.first.first) # rubocop:disable Rails/SkipsModelValidations -- no external side effects
  end

  def prepare_conversation
    @assistant = @account.captain_assistants.find_by(name: NAME) || insert(Captain::Assistant, account_id: @account.id, name: NAME, config: {})
    inbox = demo_inbox
    contact = @account.contacts.find_by(identifier: MARKER) ||
              insert(Contact, account_id: @account.id, identifier: MARKER, name: CONTACT_NAME)
    contact.update!(name: CONTACT_NAME) unless contact.name == CONTACT_NAME
    contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id) ||
                    insert(ContactInbox, contact_id: contact.id, inbox_id: inbox.id, source_id: MARKER)
    @conversation = @account.conversations.find_by(contact_inbox_id: contact_inbox.id) ||
                    insert(Conversation, account_id: @account.id, inbox_id: inbox.id, contact_id: contact.id,
                                         contact_inbox_id: contact_inbox.id, uuid: SecureRandom.uuid,
                                         additional_attributes: { captain_decisions_demo: MARKER }, last_activity_at: Time.current)
  end

  def demo_inbox
    existing = @account.inboxes.find_by(name: NAME)
    return existing if existing

    channel = insert(Channel::Api, account_id: @account.id)
    insert(Inbox, account_id: @account.id, name: NAME, channel_type: 'Channel::Api', channel_id: channel.id, enable_auto_assignment: false)
  end

  def scenario_message(scenario, index)
    source_id = "#{MARKER}:#{scenario.fetch(:name)}"
    occurred_at = 30.minutes.ago + index.minutes
    content = localized(scenario.fetch(:content))
    attributes = scenario.fetch(:attributes, {})
    attributes = attributes.deep_merge(activity: { source: { type: 'captain', name: NAME } }) if scenario[:activity]
    attributes = attributes.deep_merge(ActivityMessageNames.attributes(content, 'Captain')) if scenario[:activity]
    message = @conversation.messages.find_by(source_id: source_id)
    if message
      message.update_columns(content: content, content_attributes: attributes)
      return message
    end

    insert(
      Message, account_id: @account.id, inbox_id: @conversation.inbox_id, conversation_id: @conversation.id,
               source_id: source_id, content: content,
               content_type: :text, status: :sent,
               message_type: scenario[:activity] ? :activity : :outgoing, private: scenario.fetch(:private, false),
               sender_type: 'Captain::Assistant', sender_id: @assistant.id, content_attributes: attributes,
               created_at: occurred_at
    )
  end

  def localized(value)
    return value unless value.is_a?(Hash)

    value.fetch(@account.locale == 'es' ? :es : :en)
  end

  def seed_activity_scenario(scenario, index)
    source_id = "#{MARKER}:activity:#{scenario.fetch(:name)}"
    content = localized(scenario.fetch(:content))
    content_attributes = scenario.fetch(:content_attributes, {}).deep_merge(
      ActivityMessageNames.attributes(content, localized(scenario.fetch(:names, {})))
    )
    message = @conversation.messages.find_by(source_id: source_id)
    if message
      message.update_columns(content: content, content_attributes: content_attributes)
      return message
    end

    insert(
      Message, account_id: @account.id, inbox_id: @conversation.inbox_id, conversation_id: @conversation.id,
               source_id: source_id, content: content,
               content_type: :text, status: :sent,
               message_type: :activity, private: false, sender_type: scenario.fetch(:source_type),
               sender_id: @account.users.order(:id).pick(:id),
               content_attributes: content_attributes, created_at: 20.minutes.ago + index.minutes
    )
  end

  def seed_scenario(scenario, index)
    message = scenario_message(scenario, index)
    source_id = "#{MARKER}:#{scenario.fetch(:name)}"
    @account.captain_decisions.find_or_create_by!(decision_key: source_id) do |decision|
      decision.assign_attributes(
        conversation: @conversation, assistant: @assistant, anchor_message: message,
        kind: scenario.fetch(:kind), outcome: scenario.fetch(:outcome), origin: scenario.fetch(:origin), trigger: scenario.fetch(:trigger),
        reason_code: "demo_#{scenario.fetch(:name)}", reason_text: localized(scenario[:reason]), reason_locale: @account.locale, occurred_at: message.created_at,
        evidence: scenario.fetch(:evidence, {}), technical_details: scenario.fetch(:technical),
        settings_snapshot: scenario[:activity] ? { inactivity_threshold_minutes: 30 } : {}
      )
    end
    decision = @account.captain_decisions.find_by!(decision_key: source_id)
    decision.update_columns(reason_text: localized(scenario[:reason]),
                            reason_locale: @account.locale == 'es' ? 'es' : 'en')
  end
end
