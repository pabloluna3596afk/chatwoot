require 'rails_helper'

RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  self.use_transactional_tests = false

  let!(:existing_account_ids) { Account.pluck(:id) }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:assistant) { create(:captain_assistant, account: account) }
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }

  before do
    put_account_on_plan(account, monthly_messages: 1)
    account.enable_features!(:captain_pilot, :captain_integration_v2)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    allow(runner).to receive_messages(
      generate_response: { 'response_parts' => [{ 'text' => 'Delivered', 'citation_indexes' => [] }] },
      last_run_result: nil, response_discarded?: false, handoff_completed?: false
    )
  end

  after do
    account.account_plan_usages.destroy_all
    plan = account.plan
    # Factories such as the conversation one create further accounts of their own, so clean up every account made here.
    account_ids = Account.where.not(id: existing_account_ids).pluck(:id)
    Account.where(id: account_ids).find_each(&:destroy!)
    plan.destroy!
    Audited::Audit.where(auditable_type: 'Account', auditable_id: account_ids).delete_all
    # Associations are destroyed asynchronously, so remove what they would leave behind in this non-transactional example.
    connection = ActiveRecord::Base.connection
    connection.tables.select { |table| connection.column_exists?(table, :account_id) }.each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id IN (#{account_ids.join(',')})")
    end
  end

  it 'refunds the reservation if delivery rolls back after finishing the receipt' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :pending)
    message = create(:message, conversation: conversation, message_type: :incoming)
    allow(account).to receive(:finish_captain_ai_usage!).and_wrap_original do |original, **arguments|
      original.call(**arguments)
      raise StandardError, 'delivery transaction failed'
    end

    described_class.perform_now(conversation, assistant, message.id)

    expect(account.current_usage_period.reload.responses_consumed).to eq(0)
    expect(AiUsageReservation.where(released_at: nil)).to be_empty
    expect(conversation.messages.where(private: false, content: 'Delivered')).to be_empty
    expect(conversation.reload).to be_open
  end

  it 'delivers one reply and hands off the other when two jobs compete for the last unit' do
    conversations = Array.new(2) { create(:conversation, account: account, inbox: inbox, status: :pending) }
    messages = conversations.map { |conversation| create(:message, conversation: conversation, message_type: :incoming) }
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    conversations.each(&:reload)
    ready = Queue.new
    start = Queue.new
    conversations.each do |conversation|
      allow(conversation.account).to receive(:reserve_captain_ai_usage!).and_wrap_original do |original, **arguments|
        ready << true
        start.pop
        original.call(**arguments)
      end
    end
    attempts = conversations.zip(messages).map do |conversation, message|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.perform_now(conversation, assistant, message.id)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    attempts.each(&:value)

    expect(account.current_usage_period.reload.responses_consumed).to eq(1)
    expect(conversations.map { |conversation| conversation.reload.status }).to contain_exactly('pending', 'open')
    expect(account.messages.where(private: false, content: 'Delivered').count).to eq(1)
    expect(account.messages.where(private: false, content: I18n.t('conversations.captain.handoff', locale: account.locale)).count).to eq(1)
    expect(account.messages.where(private: true).count).to eq(1)
    expect(AiUsageReservation.where(released_at: nil)).to be_empty
  ensure
    attempts&.each { |attempt| attempt.kill if attempt.alive? }
  end
end
