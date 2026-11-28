require 'rails_helper'

RSpec.describe 'Passwords API', type: :request do
  describe 'PUT /auth/password' do
    let(:account) { create(:account) }
    let!(:user) { create(:user, password: 'Test@123456', account: account) }

    def reset_token_for(user)
      raw, enc = Devise.token_generator.generate(User, :reset_password_token)
      user.update!(reset_password_token: enc, reset_password_sent_at: Time.current)
      raw
    end

    def reset_password(token)
      put user_password_path,
          params: { reset_password_token: token, password: 'NewPassword1!', password_confirmation: 'NewPassword1!' },
          as: :json
    end

    it 'issues session tokens on successful reset' do
      account.enable_features!(:api_and_webhooks)
      reset_password(reset_token_for(user))

      expect(response).to have_http_status(:success)
      expect(response.headers['access-token']).to be_present
      expect(response.parsed_body.fetch('data')).to include(
        'access_token' => user.access_token.token,
        'pubsub_token' => user.reload.pubsub_token
      )
      expect(Current.user).to be_nil
    end

    it 'rejects expired ordinary reset tokens and preserves their password and sessions' do
      headers = user.create_new_auth_token
      raw, digest = Devise.token_generator.generate(User, :reset_password_token)
      user.update!(reset_password_token: digest, reset_password_sent_at: 7.hours.ago)
      reset_password(raw)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Invalid token')
      expect(user.reload.valid_password?('Test@123456')).to be true
      expect(user.tokens).to have_key(headers['client'])
    end

    it 'revokes old sessions and tracks the new reset session' do
      old_headers = user.create_new_auth_token
      user.user_sessions.create!(client_id: old_headers['client'])
      reset_password(reset_token_for(user))
      expect(response).to have_http_status(:success)
      expect(user.reload.tokens.keys).to eq([response.headers['client']])
      expect(user.user_sessions.pluck(:client_id)).to eq([response.headers['client']])
      get '/api/v1/profile', headers: old_headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context 'when signup is unconfirmed without an invitation' do
      it 'uses the ordinary reset expiration' do
        user.update!(confirmed_at: nil)
        raw, digest = Devise.token_generator.generate(User, :reset_password_token)
        user.update!(reset_password_token: digest, reset_password_sent_at: 7.hours.ago)
        reset_password(raw)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.reload).not_to be_confirmed
      end
    end

    context 'when an invitation has not been accepted' do
      before do
        user.update!(confirmed_at: nil)
        user.account_users.first.update!(inviter: create(:user, account: account))
      end

      it 'accepts tokens within seven days' do
        raw, digest = Devise.token_generator.generate(User, :reset_password_token)
        user.update!(reset_password_token: digest, reset_password_sent_at: 2.days.ago)
        reset_password(raw)
        expect(response).to have_http_status(:success)
        expect(user.reload).to be_confirmed
      end

      it 'rejects expired invitation tokens' do
        raw, digest = Devise.token_generator.generate(User, :reset_password_token)
        user.update!(reset_password_token: digest, reset_password_sent_at: 8.days.ago)
        reset_password(raw)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.reload).not_to be_confirmed
      end

      it 'preserves the invitation and sessions after an invalid password' do
        headers = user.create_new_auth_token
        raw, digest = Devise.token_generator.generate(User, :reset_password_token)
        user.update!(reset_password_token: digest, reset_password_sent_at: 2.days.ago)
        put user_password_path,
            params: { reset_password_token: raw, password: 'short', password_confirmation: 'short' }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.reload).not_to be_confirmed
        expect(user.reset_password_token).to eq(digest)
        expect(user.tokens).to have_key(headers['client'])
        reset_password(raw)
        expect(response).to have_http_status(:success)
      end
    end

    context 'when the user has MFA without account enforcement' do
      it 'revokes sessions and requires sign in after resetting the password' do
        skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
        user.enable_two_factor!
        user.update!(otp_required_for_login: true)
        user.create_new_auth_token
        reset_password(reset_token_for(user))
        expect(response).to have_http_status(:success)
        expect(response.headers['access-token']).to be_nil
        expect(response.parsed_body['redirect_url']).to eq('/app/login')
        expect(user.reload.tokens).to be_empty
      end
    end

    context 'when account enforces MFA' do
      before do
        skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
        account.update!(enforce_mfa: true)
      end

      it 'resets the password but withholds session tokens' do
        user.create_new_auth_token
        reset_password(reset_token_for(user))

        expect(user.reload.tokens).to be_empty
        expect(response).to have_http_status(:success)
        expect(response.headers['access-token']).to be_nil
        expect(response.parsed_body['redirect_url']).to eq('/app/login')
        expect(user.reload.valid_password?('NewPassword1!')).to be true
      end

      it 'withholds tokens for enrolled users so reset cannot bypass their otp' do
        user.enable_two_factor!
        user.update!(otp_required_for_login: true)

        user.create_new_auth_token
        reset_password(reset_token_for(user))

        expect(user.reload.tokens).to be_empty
        expect(response).to have_http_status(:success)
        expect(response.headers['access-token']).to be_nil
        expect(response.parsed_body['redirect_url']).to eq('/app/login')
        expect(user.reload.valid_password?('NewPassword1!')).to be true
      end
    end
  end
end
