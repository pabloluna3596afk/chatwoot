require 'rails_helper'

RSpec.describe GoogleCalendar::IntegrationHelper, :real_redis, type: :helper do
  let(:user) { instance_double(User, id: 23) }
  let(:browser_session) { {} }
  let(:helper) { Struct.new(:current_user, :session).new(user, browser_session).extend(described_class) }
  let(:token) { helper.generate_google_calendar_token(17) }

  before do
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_CALENDAR_CLIENT_SECRET', nil).and_return('calendar-test-secret')
  end

  it 'binds a short lived nonce to the initiating account, user and session' do
    payload = JWT.decode(token, 'calendar-test-secret', true, algorithm: 'HS256').first
    expect(payload).to include('sub' => 17, 'user_id' => 23, 'exp' => payload['iat'] + 600)
    expect(payload['jti']).to be_present
    expect(helper.verify_google_calendar_token(token)).to eq(payload)
  end

  it 'rejects reuse after consuming a state' do
    helper.verify_google_calendar_token(token)
    expect { helper.verify_google_calendar_token(token) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
  end

  it 'expires by the signed deadline even if Redis has not expired yet' do
    token
    travel 11.minutes do
      expect { helper.verify_google_calendar_token(token) }.to raise_error do |error|
        expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
      end
    end
  end

  it 'rejects a state whose Redis TTL has elapsed' do
    payload = JWT.decode(token, nil, false).first
    Redis::Alfred.with { |conn| conn.pexpire("google_calendar:oauth:#{payload['jti']}", 1) }
    sleep 0.02
    expect { helper.verify_google_calendar_token(token) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
  end

  it 'rejects a different session and consumes the attempt' do
    token
    original = browser_session.delete(:google_calendar_oauth_session)
    expect { helper.verify_google_calendar_token(token) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
    browser_session[:google_calendar_oauth_session] = original
    expect { helper.verify_google_calendar_token(token) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
  end

  it 'rejects a different authenticated user' do
    token
    allow(helper).to receive(:current_user).and_return(instance_double(User, id: 24))
    expect { helper.verify_google_calendar_token(token) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
  end

  it 'rejects a substituted account even when signed with the same secret' do
    payload = JWT.decode(token, nil, false).first.merge('sub' => 18)
    altered = JWT.encode(payload, 'calendar-test-secret', 'HS256')
    expect { helper.verify_google_calendar_token(altered) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
  end

  it 'rejects a modified signature' do
    altered = "#{token.split('.')[0..1].join('.')}.invalid"
    expect { helper.verify_google_calendar_token(altered) }.to raise_error do |error|
      expect(error.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')
    end
  end

  it 'allows only one simultaneous consumer with real Redis' do
    token
    consumers = Array.new(8) do
      Thread.new do
        helper.verify_google_calendar_token(token)
        :accepted
      rescue StandardError => e
        expect(e.class.name).to eq('GoogleCalendar::IntegrationHelper::InvalidState')

        :rejected
      end
    end
    expect(consumers.map(&:value).tally).to eq(accepted: 1, rejected: 7)
  end
end
