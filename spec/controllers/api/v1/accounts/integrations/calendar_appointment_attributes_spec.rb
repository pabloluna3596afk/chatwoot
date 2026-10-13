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
end
