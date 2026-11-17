# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::MessagePricingSummary do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:service) { described_class.new(inbox) }

  around do |example|
    travel_to(Time.zone.local(2026, 11, 17, 12)) { example.run }
  end

  it 'groups billable and free messages by category and separates app echoes' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { whatsapp_pricing: { category: 'service', billable: true } })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { whatsapp_pricing: { category: 'marketing', billable: false } })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_attributes: { external_echo: true })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_attributes: { external_echo: true },
                     additional_attributes: { whatsapp_pricing: { category: 'service', billable: true } })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

    result = service.perform.fetch(:months).first

    expect(result).to include(month: '2026-11', outgoing: 5, with_pricing: 3, app_sent: 1)
    expect(result[:categories]).to contain_exactly(
      { category: 'service', billable: 2, free: 0 },
      { category: 'marketing', billable: 0, free: 1 }
    )
  end

  it 'ignores private, incoming, activity, failed, other-inbox, and other-account messages' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     private: true)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     status: :failed)
    other_inbox = create(:inbox, account: account)
    create(:message, account: account, inbox: other_inbox, message_type: :outgoing)
    other_account = create(:account)
    create(:message, account: other_account, message_type: :outgoing)

    expect(service.perform.fetch(:months).first).to include(outgoing: 0, with_pricing: 0, app_sent: 0, categories: [])
  end

  it 'returns all requested months and excludes messages outside the range' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     created_at: Time.zone.local(2026, 11, 5))
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     created_at: Time.zone.local(2026, 8, 31))

    expect(service.perform(months: 3).fetch(:months)).to eq(
      [
        { month: '2026-11', outgoing: 1, with_pricing: 0, app_sent: 0, categories: [] },
        { month: '2026-10', outgoing: 0, with_pricing: 0, app_sent: 0, categories: [] },
        { month: '2026-09', outgoing: 0, with_pricing: 0, app_sent: 0, categories: [] }
      ]
    )
  end

  it 'treats missing category or an invalid billable value as missing price data' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { whatsapp_pricing: { billable: true } })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { whatsapp_pricing: { category: 'service', billable: 'unknown' } })

    expect(service.perform.fetch(:months).first).to include(outgoing: 2, with_pricing: 0, app_sent: 0, categories: [])
  end

  it 'keeps unknown Meta categories and defaults invalid month counts to three' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { whatsapp_pricing: { category: 'foo', billable: true } })

    expect(service.perform(months: 'invalid').fetch(:months).length).to eq(3)
    expect(service.perform(months: 0).fetch(:months).length).to eq(3)
    expect(service.perform(months: 50).fetch(:months).length).to eq(3)
    expect(service.perform.fetch(:months).first[:categories]).to eq(
      [{ category: 'foo', billable: 1, free: 0 }]
    )
  end
end
