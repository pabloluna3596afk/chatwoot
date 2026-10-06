class Whatsapp::Flows::SendFlowService
  class Error < StandardError; end

  TEXT_LIMITS = { 'header' => 60, 'body' => 1024, 'cta' => 20 }.freeze

  def initialize(conversation:, sender:, params: {})
    @conversation = conversation
    @sender = sender
    @params = params
  end

  def eligible_flows
    channel = @conversation.inbox.channel
    raise Error, 'WhatsApp Cloud required' unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

    @conversation.account.whatsapp_flows.joins(:whatsapp_flow_publications)
                 .where(whatsapp_flow_publications: { waba_id: channel.provider_config.fetch('business_account_id'), status: 'published' })
                 .where('whatsapp_flow_publications.published_at >= whatsapp_flows.updated_at')
                 .order(:name)
  end

  def perform
    raise Error, I18n.t('errors.whatsapp.message_outside_messaging_window') unless @conversation.can_reply?
    raise Error, 'Invalid flow id' unless @params['whatsapp_flow_id'].is_a?(Integer)

    flow = eligible_flows.find_by(id: @params['whatsapp_flow_id'])
    raise Error, 'A currently published flow is required' unless flow

    flow.with_lock do
      raise Error, 'A currently published flow is required' unless eligible_flows.exists?(id: flow.id)
      raise Error, 'Invalid field mapping' unless flow.definition_check.valid?

      create_message(flow)
    end
  end

  private

  def create_message(flow)
    texts = message_texts(flow)
    message = Messages::MessageBuilder.new(@sender, @conversation, { content: texts['body'] }).perform
    message.update!(additional_attributes: message.additional_attributes.merge('whatsapp_flow' => snapshot(flow, texts)))
    message
  end

  def message_texts(flow)
    defaults = { 'header' => '', 'body' => flow.name, 'cta' => I18n.t('conversations.messages.whatsapp.flow_send.open') }
    texts = defaults.merge(@params.except('whatsapp_flow_id'))
    TEXT_LIMITS.each do |key, limit|
      value = texts[key]
      raise Error, "Invalid #{key} (maximum #{limit} characters)" unless value.is_a?(String) && value.length <= limit
      raise Error, "#{key} required" if key != 'header' && value.strip.empty?
    end
    raise Error, 'CTA cannot contain emoji' if texts['cta'].match?(Whatsapp::Flows::Spec::EMOJI)

    texts
  end

  def snapshot(flow, texts)
    publication = flow.whatsapp_flow_publications.find_by!(waba_id: @conversation.inbox.channel.provider_config.fetch('business_account_id'))
    fields = Whatsapp::Flows::Spec.fields(flow.definition).filter_map do |field|
      field[:definition] if field[:definition]['save_to']
    end
    texts.merge('id' => flow.id, 'name' => flow.name, 'meta_flow_id' => publication.meta_flow_id,
                'screen' => flow.flow_json.fetch('screens').first.fetch('id'), 'fields' => fields)
  end
end
