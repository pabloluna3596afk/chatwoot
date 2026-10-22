require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::ActivityMessageService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, name: 'Soporte') }
  let(:inbox) { create(:inbox, account: account, name: 'Ventas WhatsApp') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def build(action_type)
    described_class.new(conversation: conversation, action_type: action_type, user: user, event_data: { summary: 'prueba' })
  end

  it 'names the inbox the appointment was created from' do
    expect { build(:event_created).perform }.to have_enqueued_job(Conversations::ActivityMessageJob).with(
      conversation,
      hash_including(content: 'Soporte created calendar event "prueba" from the "Ventas WhatsApp" inbox')
    )
  end

  it 'keeps the update and delete notes unchanged' do
    expect { build(:event_updated).perform }.to have_enqueued_job(Conversations::ActivityMessageJob).with(
      conversation,
      hash_including(content: 'Soporte updated calendar event "prueba"')
    )
  end
end
