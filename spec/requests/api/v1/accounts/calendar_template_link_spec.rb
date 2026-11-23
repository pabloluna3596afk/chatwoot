require 'rails_helper'

RSpec.describe 'Calendar template linking API', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/template_drafts/link" }
  let(:template) do
    { 'id' => 'selected-id', 'name' => 'custom_confirmation', 'language' => 'es', 'category' => 'UTILITY', 'status' => 'APPROVED',
      'parameter_format' => 'NAMED', 'components' => [
        { 'type' => 'BODY', 'text' => 'Hola {{nombre}}, cita {{cita}} el {{fecha}} a las {{hora}}.' },
        { 'type' => 'BUTTONS', 'buttons' => %w[Confirmar Reagendar Cancelar].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
      ] }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: [template])
  end
  let(:input) { { function: 'confirmation', channel_id: channel.id, template_name: template['name'], remote_template_id: template['id'] } }

  it 'links an explicitly selected version and returns real destination readiness' do
    post path, headers: admin.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:ok)
    row = response.parsed_body['results']['confirmation']
    expect(row).to include('ready_destinations' => 1, 'total_destinations' => 1)
    expect(row['destinations'].first).to include('state' => 'usable', 'via' => 'linked')
    resource = account.calendar_template_resources.sole
    original = resource.attributes
    expect { post path, headers: admin.create_new_auth_token, params: input, as: :json }.not_to change(CalendarTemplateResource, :count)
    expect(resource.reload.attributes).to eq(original)
    resolver = Calendar::TemplateResources.new(account: account, function: :confirmation, language: 'es', channel: channel)
    expect(resolver.resolve).to eq(template)
  end

  it 'selects the submitted remote identity of an owned draft without following local edits' do
    draft = create(:whatsapp_template_draft, account: account, name: template['name'], waba_id: channel.provider_config['business_account_id'])
    draft.submissions.create!(account: account, revision: 0, waba_id: draft.waba_id, name: draft.name, language: 'es',
                              snapshot: { 'name' => draft.name }, payload_digest: 'digest', status: 'submitted',
                              remote_status: 'APPROVED', remote_id: template['id'])
    draft.update!(name: 'edited_local_name')
    post path, headers: admin.create_new_auth_token, params: input.except(:template_name, :remote_template_id).merge(draft_id: draft.id), as: :json
    expect(response).to have_http_status(:ok)
    expect(account.calendar_template_resources.sole).to have_attributes(status: 'linked', whatsapp_template_draft_id: draft.id,
                                                                       template_name: template['name'])
  end

  { 'category' => 'MARKETING', 'status' => 'PENDING', 'parameter_format' => 'POSITIONAL' }.each do |field, value|
    it "rejects an incompatible #{field} with its contract reason" do
      channel.update!(message_templates: [template.merge(field => value)])
      post path, headers: admin.create_new_auth_token, params: input, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(field)
      expect(account.calendar_template_resources.sole.status).to eq('incompatible')
    end
  end

  %w[variables buttons].each do |reason|
    it "rejects incompatible #{reason}" do
      candidate = template.deep_dup
      candidate['components'].first['text'] += ' {{email}}' if reason == 'variables'
      candidate['components'].last['buttons'].reverse! if reason == 'buttons'
      channel.update!(message_templates: [candidate])
      post path, headers: admin.create_new_auth_token, params: input, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(reason)
    end
  end

  it 'rejects a channel from another account without writing a resource' do
    other = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false)
    post path, headers: admin.create_new_auth_token, params: input.merge(channel_id: other.id), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_channel')
    expect(account.calendar_template_resources).to be_empty
  end

  it 'rejects a non Cloud channel' do
    channel.update!(provider: 'default')
    post path, headers: admin.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('cloud_channel_required')
  end

  it 'rejects a draft from another account' do
    draft = create(:whatsapp_template_draft)
    post path, headers: admin.create_new_auth_token, params: input.except(:template_name, :remote_template_id).merge(draft_id: draft.id), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_draft')
    expect(account.calendar_template_resources).to be_empty
  end

  it 'rejects draft destination and language mismatches before linking' do
    draft = create(:whatsapp_template_draft, account: account)
    selection = input.except(:template_name, :remote_template_id).merge(draft_id: draft.id)
    post path, headers: admin.create_new_auth_token, params: selection, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('destination_mismatch')
    draft.update!(waba_id: channel.provider_config['business_account_id'], language: 'en')
    post path, headers: admin.create_new_auth_token, params: selection, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('language')
    expect(account.calendar_template_resources).to be_empty
  end

  it 'requires exactly one selection with documented JSON types' do
    invalid = [input.merge(channel_id: channel.id.to_s), input.merge(function: 'unknown'),
               input.merge(draft_id: 1), input.except(:remote_template_id)]
    invalid.each do |bad|
      post path, headers: admin.create_new_auth_token, params: bad, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_input')
    end
  end

  it 'requires authentication' do
    post path, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects agents and administrators of other accounts without exposing resources' do
    users = [create(:user, account: account, role: :agent), create(:user, account: create(:account), role: :administrator)]
    users.each do |user|
      post path, headers: user.create_new_auth_token, params: input, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(account.calendar_template_resources).to be_empty
    end
  end
end
