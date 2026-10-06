# "Probar": sends the flow as an interactive flow message to a phone number through one Cloud channel, without publishing.
# A flow that is still a draft in Meta is sent with mode=draft (the current Flow JSON is uploaded first); one already
# published and unchanged is sent as it is; one published and changed since is sent from a draft clone (see
# PublishToMetaService#prepare_for_test). Testing never requires publishing.
#
# Meta only delivers it inside the 24 h window of that number; its refusal (e.g. 131047) comes back as the error.
class Whatsapp::Flows::TestFlowService
  def initialize(flow, channel, phone_number)
    @flow = flow
    @channel = channel
    @phone_number = phone_number.to_s.delete('^0-9')
    @client = Whatsapp::Flows::MetaClient.new(channel)
  end

  def perform
    return failure('Phone number required') if @phone_number.blank?

    publication, meta_flow_id, mode = Whatsapp::Flows::PublishToMetaService.new(@flow, @channel).prepare_for_test
    return failure(error_text(publication)) if meta_flow_id.blank? || publication.validation_errors?

    response = @client.send_message(payload(meta_flow_id, mode))
    { success: true, message_id: response['messages']&.first&.dig('id') }
  rescue Whatsapp::Flows::MetaClient::Error => e
    failure(e.message)
  end

  private

  def payload(meta_flow_id, mode)
    { messaging_product: 'whatsapp', recipient_type: 'individual', to: @phone_number, type: 'interactive',
      interactive: { type: 'flow', body: { text: @flow.name },
                     action: { name: 'flow', parameters: { flow_message_version: '3', flow_id: meta_flow_id, flow_cta: 'Abrir', mode: mode,
                                                           flow_action: 'navigate', flow_action_payload: { screen: first_screen_id } } } } }
  end

  # The screen ids are the ones the exporter gives them (SCREEN_ + letters), so read them from the exported JSON.
  def first_screen_id
    @flow.flow_json['screens'].first['id']
  end

  def error_text(publication)
    return 'Meta did not accept the flow' if publication.validation_errors.empty?

    publication.validation_errors.map { |error| [error['path'], error['message'] || error['error']].compact.join(': ') }.join('; ')
  end

  def failure(message)
    { success: false, error: message }
  end
end
