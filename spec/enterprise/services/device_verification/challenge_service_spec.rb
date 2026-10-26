require 'rails_helper'

RSpec.describe DeviceVerification::ChallengeService do
  let(:user) { create(:user, password: 'Password1!') }
  let(:mailer_message) { instance_double(ActionMailer::MessageDelivery, deliver_now: true, deliver_later: true) }
  let(:email_codes) { [] }

  before do
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(123_456)
    allow(Enterprise::DeviceVerificationMailer).to receive(:verification_code) do |_user, ciphertext, _meta|
      email_codes << DeviceVerification.decrypt_code(ciphertext)
      mailer_message
    end
  end

  def issue_token
    described_class.new(user: user).issue!
  end

  it 'issues an expiring token and a six-digit code without storing the code in plaintext' do
    token = issue_token
    claims = DeviceVerification::TokenService.new(token: token).decode_claims

    expect(claims[:user_id]).to eq(user.id)
    expect(email_codes.first).to match(/\A\d{6}\z/)
    key = described_class.code_key(user, claims[:jti])
    expect(Redis::Alfred.get(key)).not_to eq(email_codes.first)
  end

  it 'allows at most ten issued challenges in 24 hours' do
    10.times { expect(issue_token).to be_present }

    expect(issue_token).to be_nil
  end

  it 'consumes a valid code exactly once' do
    token = issue_token

    expect(described_class.redeem(token: token, code: email_codes.last)).to eq(user: user)
    expect(described_class.redeem(token: token, code: email_codes.last)).to eq(error: :expired)
  end

  it 'locks after five incorrect attempts' do
    token = issue_token
    5.times { expect(described_class.redeem(token: token, code: '000000')[:error]).to eq(:invalid_code) }

    expect(described_class.redeem(token: token, code: email_codes.last)[:error]).to eq(:locked)
  end

  it 'invalidates outstanding challenges after a password change' do
    token = issue_token
    user.update!(password: 'NewPassword1!')

    expect(described_class.redeem(token: token, code: email_codes.last)[:error]).to eq(:stale)
  end
end
