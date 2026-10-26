require 'rails_helper'

RSpec.describe Enterprise::DeviceVerificationMailer do
  let(:user) { create(:user, email: 'agent@example.com') }
  let(:encrypted_code) { DeviceVerification.encrypt_code('482913') }

  around do |example|
    with_modified_env('SMTP_ADDRESS' => 'smtp.example.com') { example.run }
  end

  it 'sends the code to the user and renders device details' do
    mail = described_class.verification_code(
      user, encrypted_code, ip: '203.0.113.4', browser_name: 'Firefox', platform_name: 'Linux'
    ).message

    expect(mail.to).to eq(['agent@example.com'])
    expect(mail.subject).to include('verification code')
    expect(mail.body.encoded).to include('482913', '203.0.113.4', 'Firefox')
  end

  it 'does not create a challenge email when SMTP is not configured' do
    with_modified_env('SMTP_ADDRESS' => nil) do
      expect { described_class.verification_code(user, encrypted_code).message }
        .to raise_error(DeviceVerification::DeliveryError, 'SMTP is not configured')
    end
  end
end
