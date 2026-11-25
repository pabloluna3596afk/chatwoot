require 'rails_helper'

RSpec.describe BackgroundTasks::Notifier do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  it 'broadcasts through the dispatcher to only this account agents and administrators' do
    Current.user = nil
    create(:user, account: create(:account), role: :administrator)
    expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, event_name, payload|
      expect(tokens).to contain_exactly(admin.pubsub_token, agent.pubsub_token)
      expect(event_name).to eq('background_task.updated')
      expect(payload).to eq(
        account_id: account.id,
        task: { id: 'import:42', kind: 'import', title: 'Contacts', status: 'running', detail: nil, link: nil }
      )
    end
    described_class.publish(account: account, id: 'import:42', kind: 'import', title: 'Contacts', status: 'running')
  end

  it 'rejects invalid statuses before dispatching' do
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch)
    expect do
      described_class.publish(account: account, id: 'import:42', kind: 'import', title: 'Contacts', status: 'pending')
    end.to raise_error(ArgumentError, 'Invalid background task status')
  end
end
