require 'rails_helper'

RSpec.describe Conversations::FilterService do
  # The status filter follows what the agent sees: a conversation Captain attends reads as open.
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:plain_inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }

  def conversation(inbox:, status:, ai_assignee: nil)
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).tap do |record|
      record.update_columns( # rubocop:disable Rails/SkipsModelValidations
        status: Conversation.statuses.fetch(status.to_s), ai_assignee_type: ai_assignee&.class&.name, assignee_agent_bot_id: ai_assignee&.id
      )
    end
  end

  def listed(operator, values)
    payload = [{ attribute_key: 'status', filter_operator: operator, values: values, query_operator: nil }.with_indifferent_access]
    described_class.new({ payload: payload }, admin, account).perform[:conversations].map(&:id)
  end

  let!(:attended) { conversation(inbox: inbox, status: :pending, ai_assignee: assistant) }
  let!(:plain_open) { conversation(inbox: plain_inbox, status: :open) }
  let!(:plain_pending) { conversation(inbox: plain_inbox, status: :pending) }
  let!(:resolved) { conversation(inbox: plain_inbox, status: :resolved) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    Current.account = account
  end

  it 'lists what Captain attends under open and not under pending' do
    expect(listed('equal_to', ['open'])).to contain_exactly(attended.id, plain_open.id)
    expect(listed('equal_to', ['pending'])).to contain_exactly(plain_pending.id)
  end

  it 'keeps the other statuses as they are' do
    expect(listed('equal_to', ['resolved'])).to contain_exactly(resolved.id)
    expect(listed('equal_to', %w[open resolved])).to contain_exactly(attended.id, plain_open.id, resolved.id)
  end

  it 'excludes by what the agent sees with not_equal_to' do
    expect(listed('not_equal_to', ['open'])).to contain_exactly(plain_pending.id, resolved.id)
    expect(listed('not_equal_to', ['pending'])).to contain_exactly(attended.id, plain_open.id, resolved.id)
  end
end
