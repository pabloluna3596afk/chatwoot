require 'rails_helper'

RSpec.describe 'Super Admin', type: :request do
  describe '/super_admin' do
    it 'renders the login page' do
      with_modified_env LOGRAGE_ENABLED: 'true' do
        get '/super_admin/sign_in'
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'POST /super_admin/sign_in' do
    let(:super_admin) { create(:super_admin, password: 'Password1!') }

    it 'redirects to the dashboard on successful login' do
      post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'Password1!' } }
      expect(response).to redirect_to(super_admin_root_path)
    end

    it 'redirects back to the login page on invalid credentials' do
      post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'wrong' } }
      expect(response).to redirect_to(super_admin_session_path)
    end
  end

  describe 'POST /super_admin/sign_in with MFA enabled' do
    let(:super_admin) { create(:super_admin, password: 'Password1!') }
    let(:credentials) { { super_admin: { email: super_admin.email, password: 'Password1!' } } }

    before do
      skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
      super_admin.enable_two_factor!
      super_admin.update!(otp_required_for_login: true)
    end

    after do
      Redis::Alfred.delete(format(Redis::RedisKeys::SUPER_ADMIN_MFA_FAILED_ATTEMPTS, user_id: super_admin.id))
    end

    it 'requires the code after a valid password' do
      post '/super_admin/sign_in', params: credentials
      expect(response).to redirect_to(super_admin_session_path)
      get '/super_admin/sign_in'
      expect(response.body).to include('super_admin[otp_code]')
      get '/super_admin/accounts'
      expect(response).to redirect_to(super_admin_session_path)
    end

    it 'signs in with a valid authenticator code' do
      post '/super_admin/sign_in', params: credentials
      post '/super_admin/sign_in', params: { super_admin: { otp_code: super_admin.reload.current_otp } }
      expect(response).to redirect_to(super_admin_root_path)
    end

    it 'consumes a backup code only once' do
      backup_code = super_admin.generate_backup_codes!.first
      post '/super_admin/sign_in', params: credentials
      post '/super_admin/sign_in', params: { super_admin: { otp_code: backup_code.downcase } }
      expect(response).to redirect_to(super_admin_root_path)
      delete '/super_admin/sign_out'
      post '/super_admin/sign_in', params: credentials
      post '/super_admin/sign_in', params: { super_admin: { otp_code: backup_code } }
      expect(response).to redirect_to(super_admin_session_path)
    end

    it 'rejects invalid and blank codes' do
      post '/super_admin/sign_in', params: credentials
      ['invalid-code', ''].each do |code|
        post '/super_admin/sign_in', params: { super_admin: { otp_code: code } }
        expect(response).to redirect_to(super_admin_session_path)
        expect(flash[:error]).to eq(I18n.t('super_admin.login.mfa_invalid'))
      end
    end

    it 'limits attempts across password challenges' do
      post '/super_admin/sign_in', params: credentials
      5.times { post '/super_admin/sign_in', params: { super_admin: { otp_code: 'invalid-code' } } }
      post '/super_admin/sign_in', params: credentials
      post '/super_admin/sign_in', params: { super_admin: { otp_code: super_admin.reload.current_otp } }
      expect(response).to redirect_to(super_admin_session_path)
      expect(flash[:error]).to eq(I18n.t('super_admin.login.mfa_attempts_exhausted'))
    end

    it 'rejects an expired challenge' do
      post '/super_admin/sign_in', params: credentials
      travel 6.minutes do
        post '/super_admin/sign_in', params: { super_admin: { otp_code: super_admin.reload.current_otp } }
        expect(flash[:error]).to eq(I18n.t('super_admin.login.mfa_expired'))
      end
    end

    it 'invalidates the challenge when the password changes' do
      post '/super_admin/sign_in', params: credentials
      super_admin.update!(password: 'NewPassword1!', password_confirmation: 'NewPassword1!')
      post '/super_admin/sign_in', params: { super_admin: { otp_code: super_admin.reload.current_otp } }
      expect(flash[:error]).to eq(I18n.t('super_admin.login.mfa_expired'))
    end

    it 'rejects codes without a password challenge' do
      post '/super_admin/sign_in', params: { super_admin: { otp_code: super_admin.current_otp } }
      expect(flash[:error]).to eq(I18n.t('super_admin.login.mfa_expired'))
    end
  end

  describe 'unused Super Admin Devise routes' do
    it 'does not expose password reset, registration or confirmation' do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:super_admin_password_path)
      expect(Rails.application.routes.url_helpers).not_to respond_to(:super_admin_registration_path)
      expect(Rails.application.routes.url_helpers).not_to respond_to(:super_admin_confirmation_path)
    end
  end
end
