require 'rails_helper'

RSpec.describe 'Calendar template availability in inboxes', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:template) do
    { 'id' => 'remote', 'name' => 'confirmacion_v2', 'language' => 'es', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'parameter_format' => 'NAMED', 'components' => [
        { 'type' => 'BODY', 'text' => '{{nombre}} {{cita}} {{fecha}} {{hora}}' },
        { 'type' => 'BUTTONS', 'buttons' => %w[Confirmar Reagendar Cancelar].map { |label| { 'type' => 'QUICK_REPLY', 'text' => label } } }
      ] }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'business_account_id' => 'waba' }, message_templates: [template])
  end
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}" }

  it 'exposes the approved current name and blocks frontend availability after a category change' do
    Calendar::TemplateResources.new(account: account, function: :confirmation, language: 'es', channel: channel)
                               .link!(template_name: template['name'], remote_template_id: template['id'])
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['calendar_confirmation_template']).to include('name' => 'confirmacion_v2', 'language' => 'es', 'available' => true)

    channel.update!(message_templates: [template.merge('category' => 'MARKETING')])
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('calendar_confirmation_template', 'available')).to be(false)
  end
end
