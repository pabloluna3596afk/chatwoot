require 'rails_helper'

RSpec.describe Captain::Messaging::AssistantPayload do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'batches resource lookups for ten connected inboxes' do
    10.times do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false, message_templates: [],
                                          provider_config: { 'business_account_id' => '123' })
      create(:captain_inbox, captain_assistant: assistant, inbox: channel.inbox)
    end
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
    end

    result = described_class.new(assistant).as_json

    ActiveSupport::Notifications.unsubscribe(subscriber)
    expect(result[:inboxes].size).to eq(10)
    expect(queries.size).to be < 25
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
