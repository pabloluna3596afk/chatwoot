require 'rails_helper'

RSpec.describe 'Device verification on password sign-in', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: 'Password1!') }
  let(:email_codes) { [] }
  let(:email_code) { email_codes.last }
  let(:mailer_message) { instance_double(ActionMailer::MessageDelivery, deliver_now: true, deliver_later: true) }

  before do
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(123_456)
    allow(DeviceVerification).to receive(:enabled?).and_return(true)
    allow(Enterprise::DeviceVerificationMailer).to receive(:verification_code) do |_user, ciphertext, _meta|
      email_codes << DeviceVerification.decrypt_code(ciphertext)
      mailer_message
    end
    allow(Enterprise::DeviceVerificationMailer).to receive(:new_device).and_return(mailer_message)
  end

  def sign_in!(email: user.email, password: 'Password1!', extra: {})
    post '/auth/sign_in', params: { email: email, password: password }.merge(extra), as: :json
  end

  def redeem!(token, code: email_code, extra: {})
    post '/auth/sign_in', params: { mfa_token: token, otp_code: code }.merge(extra), as: :json
  end

  it 'issues a 206 email challenge before creating a session for a new device' do
    sign_in!

    exception = Nokogiri::HTML(response.body).at_css('.exception-message .message')&.text
    expect(response).to have_http_status(:partial_content), exception
    expect(response.parsed_body).to include('mfa_required' => true, 'verification_channel' => 'email')
    expect(response.parsed_body['mfa_token']).to be_present
    expect(response.headers['access-token']).to be_nil
    expect(email_code).to match(/\A\d{6}\z/)
  end

  it 'authenticates once with the correct code and sets a 30-day trust cookie' do
    sign_in!
    redeem!(response.parsed_body.fetch('mfa_token'))

    expect(response).to have_http_status(:success)
    expect(response.headers['access-token']).to be_present
    expect(response.cookies.keys).to include("cw_dv_#{user.id}")

    sign_in!
    expect(response).to have_http_status(:success)
    expect(Enterprise::DeviceVerificationMailer).to have_received(:verification_code).once
  end

  it 'does not trust the device when the user unchecks remember device' do
    sign_in!
    redeem!(response.parsed_body.fetch('mfa_token'), extra: { remember_device: false })

    expect(response).to have_http_status(:success)
    expect(response.cookies.keys).not_to include("cw_dv_#{user.id}")
  end

  it 'rejects an incorrect code without creating an authenticated session' do
    sign_in!
    redeem!(response.parsed_body.fetch('mfa_token'), code: '000000')

    expect(response).to have_http_status(:bad_request)
    expect(response.headers['access-token']).to be_nil
  end

  it 'fails closed and releases the issuance budget when verification email delivery fails' do
    allow(mailer_message).to receive(:deliver_now).and_raise(StandardError, 'SMTP unavailable')

    sign_in!

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to eq(I18n.t('errors.device_verification.delivery_unavailable'))
    key = format(Redis::RedisKeys::DEVICE_VERIFICATION_ISSUANCE, user_id: user.id)
    expect(Redis::Alfred.get(key).to_i).to eq(0)
  end

  it 'locks a challenge after five incorrect attempts' do
    sign_in!
    token = response.parsed_body.fetch('mfa_token')
    5.times { redeem!(token, code: '000000') }
    redeem!(token)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body['error']).to eq(I18n.t('errors.device_verification.locked'))
  end

  it 're-challenges a trusted cookie after the user trust version changes' do
    sign_in!
    redeem!(response.parsed_body.fetch('mfa_token'))
    User.update_counters(user.id, device_trust_version: 1) # rubocop:disable Rails/SkipsModelValidations

    sign_in!

    expect(response).to have_http_status(:partial_content)
  end

  it 'rejects an outstanding verification token after trust revocation' do
    sign_in!
    token = response.parsed_body.fetch('mfa_token')
    User.update_counters(user.id, device_trust_version: 1) # rubocop:disable Rails/SkipsModelValidations

    redeem!(token)

    expect(response).to have_http_status(:bad_request)
    expect(response.headers['access-token']).to be_nil
  end

  it 'does not challenge Panel AI sign-in or support impersonation tokens' do
    post '/auth/sign_in', params: { email: user.email, sso_auth_token: user.generate_sso_auth_token }, as: :json
    expect(response).to have_http_status(:success)
    expect(Enterprise::DeviceVerificationMailer).not_to have_received(:verification_code)

    post '/auth/sign_in', params: { email: user.email, sso_auth_token: user.generate_sso_auth_token(impersonation: true) }, as: :json
    expect(response).to have_http_status(:success)
    expect(Enterprise::DeviceVerificationMailer).not_to have_received(:verification_code)
  end

  it 'does not challenge SAML users attempting password sign-in' do
    create(:account_saml_settings, account: account)
    saml_user = create(:user, email: 'saml@example.com', provider: 'saml', password: 'Password1!', account: account)

    sign_in!(email: saml_user.email)

    expect(response).to have_http_status(:unauthorized)
    expect(Enterprise::DeviceVerificationMailer).not_to have_received(:verification_code)
  end

  it 'leaves password sign-in unchanged when the global switch is off' do
    allow(DeviceVerification).to receive(:enabled?).and_return(false)

    sign_in!

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).not_to have_key('verification_channel')
    expect(Enterprise::DeviceVerificationMailer).not_to have_received(:verification_code)
  end

  it 'keeps an enrolled MFA user on the TOTP challenge path' do
    skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
    user.enable_two_factor!
    user.update!(otp_required_for_login: true)

    sign_in!

    expect(response).to have_http_status(:partial_content)
    expect(response.parsed_body).not_to have_key('verification_channel')
    expect(Enterprise::DeviceVerificationMailer).not_to have_received(:verification_code)
  end
end
