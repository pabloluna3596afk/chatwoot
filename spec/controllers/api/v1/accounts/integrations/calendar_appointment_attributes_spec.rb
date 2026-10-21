require 'rails_helper'

RSpec.describe 'Calendar appointment attributes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/appointment_attributes" }

  it 'requires authentication' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows agents to consult the saved selection' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('keys' => nil, 'enabled_keys' => [], 'results' => {})
  end

  it 'activates selected attributes and returns their provisioning results' do
    patch url, params: { keys: %w[ultima_cita total_citas] }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['enabled_keys']).to eq(%w[ultima_cita total_citas])
    expect(response.parsed_body['results']['ultima_cita']['status']).to eq('created')
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq(account.reload.appointment_attributes)
  end

  it 'returns reused attributes and type conflicts' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                         attribute_key: 'ultima_cita', attribute_display_type: :text)
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                         attribute_key: 'total_citas', attribute_display_type: :number)

    patch url, params: { keys: %w[ultima_cita total_citas] }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['results']['ultima_cita']['status']).to eq('conflict')
    expect(response.parsed_body['results']['total_citas']['status']).to eq('reused')
    expect(response.parsed_body['enabled_keys']).to eq(['total_citas'])
  end

  it 'disables with an empty selection without deleting attributes' do
    Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: ['total_citas'])

    expect do
      patch url, params: { keys: [] }, headers: admin.create_new_auth_token, as: :json
    end.not_to change(CustomAttributeDefinition, :count)
    expect(response.parsed_body['enabled_keys']).to be_empty
  end

  it 'requires an administrator to change the selection' do
    patch url, params: { keys: ['total_citas'] }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.appointment_attributes).to be_nil
  end

  [nil, 'total_citas', ['unknown'], [1], %w[total_citas total_citas], { total_citas: true }].each do |keys|
    it "rejects malformed keys #{keys.inspect} without provisioning" do
      expect do
        patch url, params: { keys: keys }, headers: admin.create_new_auth_token, as: :json
      end.not_to change(CustomAttributeDefinition, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.appointment_attributes).to be_nil
    end
  end
  it 'keeps all four definitions stable when onboarding is retried after reloading' do
    keys = Calendar::AppointmentAttributes::Definitions::TYPES.keys
    patch url, params: { keys: keys }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['results'].values.pluck('status')).to eq(Array.new(4, 'created'))
    ids = account.custom_attribute_definitions.order(:id).ids

    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['keys']).to eq(keys)
    patch url, params: { keys: keys }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['results'].values.pluck('status')).to eq(Array.new(4, 'reused'))
    expect(account.custom_attribute_definitions.order(:id).ids).to eq(ids)
  end

  it 'distinguishes a deliberately empty saved selection from an unconfigured account' do
    patch url, params: { keys: [] }, headers: admin.create_new_auth_token, as: :json
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('keys' => [], 'enabled_keys' => [], 'results' => {})
    expect(account.custom_attribute_definitions).to be_empty
  end

  it 'preserves conflicting definitions and contact values through retries and backfill' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                                      attribute_key: 'ultima_cita', attribute_display_type: :text)
    contact = create(:contact, account: account, custom_attributes: { 'ultima_cita' => 'Customer value' })
    original = definition.attributes
    keys = Calendar::AppointmentAttributes::Definitions::TYPES.keys

    2.times do
      patch url, params: { keys: keys }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['results']['ultima_cita']['status']).to eq('conflict')
      expect(response.parsed_body['enabled_keys']).not_to include('ultima_cita')
    end
    Calendar::AppointmentAttributes::UpdateJob.perform_now(account.id, contact.id)

    expect(definition.reload.attributes).to eq(original)
    expect(contact.reload.custom_attributes['ultima_cita']).to eq('Customer value')
    expect(account.custom_attribute_definitions.count).to eq(4)
  end
end
