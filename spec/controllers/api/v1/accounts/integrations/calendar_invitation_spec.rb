require 'rails_helper'

RSpec.describe 'Calendar invitation text API', type: :request do
  let(:account) { create(:account, locale: 'es') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/calendar_connections/invitation" }

  describe 'GET invitation' do
    it 'gives the default text, in the language of the account, and the variables, to an agent too' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['template']).to be_nil
      expect(body['location']).to be_nil
      expect(body['default_template']).to include('Hola {{primer_nombre}}')
      expect(body['tokens']).to include('nombre', 'fecha', 'hora', 'enlace_meet', 'direccion')
      expect(body['max_length']).to eq(Integrations::GoogleCalendar::InvitationText::MAX_LENGTH)
    end

    it 'requires authentication' do
      get url, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH invitation' do
    it 'saves the text and the address of the account' do
      patch url, params: { template: 'Te esperamos {{nombre}}', location: 'Av. Sol 1' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(account.reload).to have_attributes(appointment_invitation_template: 'Te esperamos {{nombre}}', appointment_location: 'Av. Sol 1')
      expect(response.parsed_body).to include('template' => 'Te esperamos {{nombre}}', 'location' => 'Av. Sol 1')
    end

    it 'goes back to the default text when it is saved empty' do
      account.update!(appointment_invitation_template: 'Otro', appointment_location: 'Aquí')

      patch url, params: { template: '  ', location: '' }, headers: admin.create_new_auth_token, as: :json

      expect(account.reload.appointment_invitation_template).to be_nil
      expect(account.appointment_location).to be_nil
    end

    it 'refuses a variable that does not exist, saying which' do
      patch url, params: { template: 'Hola {{nobre}}' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invitation_unknown_tokens')
      expect(response.parsed_body['message']).to include('{{nobre}}')
      expect(account.reload.appointment_invitation_template).to be_nil
    end

    it 'refuses a text that is too long' do
      patch url, params: { template: 'a' * (Integrations::GoogleCalendar::InvitationText::MAX_LENGTH + 1) },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invitation_too_long')
    end

    it 'is for administrators only' do
      patch url, params: { template: 'Hola' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.appointment_invitation_template).to be_nil
    end
  end
end
