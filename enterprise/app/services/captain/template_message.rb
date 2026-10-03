# An approved WhatsApp template picked in an assistant's settings, turned into the message payload Chatwoot sends.
# Shared by every Captain message that, outside the 24 h window, has to be a template (appointment reminders,
# re-engagement).
#
# The reference saved in the settings is { 'name', 'language', 'processed_params' }, the same shape automations and
# campaigns use: `processed_params` holds the text of each variable of the template, body and text header, numbered
# ({{1}}) or named ({{nombre}}): { 'body' => { '1' => '{{ contact.name }}' }, 'header' => { 'titulo' => '{{ appointment.title }}' } }.
# A text may carry Liquid; it is rendered when the message is sent. Chatwoot's WhatsApp sender turns the result into the
# components Meta wants (named parameters for NAMED templates, header parameters for text headers).
class Captain::TemplateMessage
  VARIABLE = /\{\{\s*([^}\s]+)\s*\}\}/
  COMPONENTS = { 'BODY' => 'body', 'HEADER' => 'header' }.freeze

  # Raised when the saved texts no longer cover the variables of the template (it changed in Meta).
  class MappingMismatch < StandardError; end

  Variable = Struct.new(:component, :name) do
    def key
      "#{component}.#{name}"
    end
  end

  class << self
    # The approved entry of the inbox's WhatsApp templates, or nil (not found, or not approved).
    def approved(inbox, reference)
      return if reference.blank? || inbox.channel_type != 'Channel::Whatsapp'

      find(Array(inbox.channel.message_templates), reference, approved_only: true)
    end

    # The entry of any WhatsApp inbox of the account (to check the texts when the settings are saved).
    def find_in_account(account, reference)
      return if reference.blank?

      Channel::Whatsapp.where(account_id: account.id).filter_map do |channel|
        find(Array(channel.message_templates), reference, approved_only: false)
      end.first
    end

    # The variables of the body and of a text header, in order.
    def variables(entry)
      Array(entry['components']).flat_map do |component|
        kind = COMPONENTS[component['type'].to_s.upcase]
        next [] if kind.nil? || (kind == 'header' && component['format'].present? && component['format'].to_s.upcase != 'TEXT')

        component['text'].to_s.scan(VARIABLE).flatten.uniq.map { |name| Variable.new(kind, name) }
      end
    end

    # Keys ("body.1", "header.titulo") of the variables that have no text.
    def unmapped(entry, processed_params)
      params = processed_params.is_a?(Hash) ? processed_params : {}
      variables(entry).map(&:key).select do |key|
        component, name = key.split('.', 2)
        params.dig(component, name).to_s.strip.blank?
      end
    end

    # [template_params payload, text shown in the conversation]. `drops` are the Liquid objects the texts can use
    # (see .drops). A variable whose text renders empty is sent as "-" (Meta rejects empty ones). A reference saved
    # without texts (nil) uses `fallback`. Raises MappingMismatch when a variable of the template has no text.
    def build(entry, processed_params, drops, fallback: nil)
      params = processed_params.nil? ? fallback : processed_params
      missing = unmapped(entry, params)
      raise MappingMismatch, missing.join(', ') if missing.any?

      texts = variables(entry).to_h { |variable| [variable.key, render(params.dig(variable.component, variable.name), drops)] }
      [payload(entry, texts), rendered_body(entry, texts)]
    end

    # What the texts of a message about an appointment can use: {{ contact.name }}, {{ appointment.date }}...
    # `appointment` is nil for messages that are not about one (the re-engagement).
    def drops(conversation, assistant, appointment: nil)
      {
        'contact' => ContactDrop.new(conversation.contact),
        'agent' => UserDrop.new(conversation.assignee),
        'conversation' => ConversationDrop.new(conversation),
        'inbox' => InboxDrop.new(conversation.inbox),
        'account' => AccountDrop.new(conversation.account),
        'date' => DateDrop.new,
        'assistant' => { 'name' => assistant.name },
        'appointment' => appointment.to_h.stringify_keys
      }
    end

    # A text that is not valid Liquid cannot be saved. (An unknown expression, say a typo in {{ appointment.dat }},
    # is valid and renders empty, which is sent as "-".)
    def valid_liquid?(text)
      Liquid::Template.parse(text.to_s)
      true
    rescue Liquid::Error
      false
    end

    private

    def find(templates, reference, approved_only:)
      templates.find do |entry|
        entry['name'] == reference['name'] && entry['language'].to_s.casecmp?(reference['language'].to_s) &&
          (!approved_only || entry['status'].to_s.casecmp?('approved'))
      end
    end

    def render(text, drops)
      Liquid::Template.parse(text.to_s).render(drops).strip.presence || '-'
    rescue Liquid::Error
      text.to_s.strip.presence || '-'
    end

    def payload(entry, texts)
      params = %w[body header].index_with do |component|
        texts.select { |key, _| key.start_with?("#{component}.") }.transform_keys { |key| key.delete_prefix("#{component}.") }
      end.compact_blank
      { name: entry['name'], namespace: entry['namespace'], language: entry['language'], category: entry['category'],
        processed_params: params }
    end

    def rendered_body(entry, texts)
      body = Array(entry['components']).find { |component| component['type'].to_s.casecmp?('BODY') }
      text = body&.dig('text').to_s.gsub(VARIABLE) { texts["body.#{Regexp.last_match(1)}"] || '-' }
      text.presence || entry['name']
    end
  end
end
