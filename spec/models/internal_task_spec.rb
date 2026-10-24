require 'rails_helper'

RSpec.describe InternalTask do
  subject(:task) { described_class.new(conversation: conversation, title: 'Call the customer') }

  let(:conversation) { create(:conversation) }

  it 'continues requiring a creator for a manually created task' do
    expect(task).not_to be_valid
    expect(task.errors[:created_by]).to be_present
  end

  it 'accepts the existing human creator' do
    task.created_by = create(:user, account: conversation.account)

    expect(task).to be_valid
  end

  it 'allows an explicitly identified system task without a user' do
    task.metadata = { created_by_type: 'system', source_type: 'AutomationRule' }

    expect(task).to be_valid
    expect(task.push_event_data).not_to have_key(:created_by)
  end
end
