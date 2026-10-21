class Flows::DeferredSendJob < ApplicationJob
  queue_as :high

  def perform(payload)
    payload = payload.with_indifferent_access
    conversation = Conversation.find_by(id: payload[:conversation_id])
    run = FlowRun.find_by(id: payload[:flow_run_id])
    return if conversation.blank? || run.blank? || !run.active?

    resolved = resolve_payload(conversation, run, payload)
    create_message(conversation, run, payload.merge(resolved))
    Flows::ExecutionService.new(run: run).advance_after_send!(payload[:node_id])
  rescue Variables::DeliveryRenderer::Error => e
    Variables::Omission.create_note(conversation: conversation, surface: 'flow', error: e)
    Flows::ExecutionService.new(run: run).advance_after_send!(payload[:node_id], result: { 'skipped' => e.message })
  end

  private

  def resolve_payload(conversation, run, payload)
    records = { conversation: conversation, flow_run: run }
    drops = Variables::ContextFactory.new(account: conversation.account, records: records).build(surface: 'flow')
    renderer = Variables::DeliveryRenderer.new(drops: drops)
    payload.slice(:content, :buttons).to_h do |key, value|
      [key, renderer.render(value, path: key, protect_code: true)]
    end
  end

  def create_message(conversation, run, payload)
    content = payload[:content].to_s
    buttons = Array(payload[:buttons]).map do |btn|
      btn = btn.with_indifferent_access
      { 'title' => btn[:title].to_s.truncate(20), 'value' => btn[:value].presence || btn[:title].to_s }
    end

    params = {
      content: content,
      private: false,
      content_attributes: MessageSourceAttributes.for_flow(run).merge(
        flow_node_id: payload[:node_id]
      )
    }

    if buttons.any?
      params[:content_type] = 'input_select'
      params[:content_attributes][:items] = buttons.first(3)
    end

    Messages::MessageBuilder.new(nil, conversation, params).perform(variables_resolved: true)
  end
end
