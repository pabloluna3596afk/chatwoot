require 'rails_helper'

RSpec.describe Calendar::NotifyPanelAiFollowupJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh', connected_by: user
    )
  end
  let(:calendar_event) do
    connection.calendar_events.create!(
      account: account, external_calendar_id: 'cal-1', google_event_id: 'g-1', summary: 'Consulta',
      start_at: Time.zone.parse('2030-01-15T10:00:00-05:00'), end_at: Time.zone.parse('2030-01-15T10:30:00-05:00'),
      bot_followup_policy: { 'enabled' => true, 'confirmation' => true, 'reminders_minutes_before' => [120] },
      appointment_status: 'pending_confirmation'
    )
  end
  let(:ok_response) { instance_double(HTTParty::Response, success?: true) }

  before { allow(HTTParty).to receive(:post).and_return(ok_response) }

  it 'does nothing when PANEL_AI_URL is blank' do
    with_modified_env PANEL_AI_URL: '' do
      described_class.perform_now(calendar_event.id, 'created')
    end

    expect(HTTParty).not_to have_received(:post)
  end

  it 'does nothing when the calendar event no longer exists' do
    with_modified_env PANEL_AI_URL: 'https://panel.example.test' do
      described_class.perform_now(0, 'created')
    end

    expect(HTTParty).not_to have_received(:post)
  end

  it 'posts the event to Panel AI with an HMAC signature' do
    captured = nil
    allow(HTTParty).to receive(:post) do |url, options|
      captured = { url: url, options: options }
      ok_response
    end

    with_modified_env PANEL_AI_URL: 'https://panel.example.test/', PANEL_AI_WEBHOOK_SECRET: 's3cret' do
      described_class.perform_now(calendar_event.id, 'updated')
    end

    expect(captured[:url]).to eq('https://panel.example.test/api/v1/inboxhub/calendar-events')
    body = JSON.parse(captured[:options][:body])
    expect(body['event']).to eq('updated')
    expect(body['calendar_event']).to include(
      'id' => calendar_event.id, 'account_id' => account.id, 'summary' => 'Consulta',
      'appointment_status' => 'pending_confirmation',
      'bot_followup_policy' => { 'enabled' => true, 'confirmation' => true, 'reminders_minutes_before' => [120] }
    )
    expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 's3cret', captured[:options][:body])}"
    expect(captured[:options][:headers]).to include('X-Panel-AI-Signature' => expected_signature, 'Content-Type' => 'application/json')
  end

  it 'does not raise when Panel AI answers with an error' do
    allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, success?: false, code: 500, body: 'boom'))

    with_modified_env PANEL_AI_URL: 'https://panel.example.test' do
      expect { described_class.perform_now(calendar_event.id, 'created') }.not_to raise_error
    end
  end

  it 'does not raise when the request fails' do
    allow(HTTParty).to receive(:post).and_raise(Errno::ECONNREFUSED)

    with_modified_env PANEL_AI_URL: 'https://panel.example.test' do
      expect { described_class.perform_now(calendar_event.id, 'created') }.not_to raise_error
    end
  end
end
