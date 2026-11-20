require 'rails_helper'

RSpec.describe Captain::Decision do
  subject(:decision) { build(:captain_decision, account: account, conversation: conversation, assistant: assistant) }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'accepts a versioned decision without an optional session or anchor' do
    expect(decision).to be_valid
    expect { decision.save! }.to change(described_class, :count).by(1)
  end

  %i[kind outcome origin trigger version].each do |field|
    it "rejects an unknown #{field}" do
      decision[field] = field == :version ? 2 : 'unknown'
      expect(decision).not_to be_valid
      expect(decision.errors[field]).to be_present
    end
  end

  it 'limits the reason and the combined UTF-8 JSON size' do
    decision.reason_text = 'x' * 501
    expect(decision).not_to be_valid
    decision.reason_text = 'x' * 500
    decision.evidence = { tools: Array.new(50) { 'x' * 80 } }
    expect(decision).to be_valid
    decision.evidence = { tools: Array.new(51) { 'x' * 80 } }
    expect(decision).not_to be_valid
  end

  it 'rejects raw contexts, tool arguments and invalid JSON shapes' do
    [{ run_context: [] }, { tools: [{ name: 'resolve', arguments: {} }] }, [], { complete: 'true' }].each do |evidence|
      decision.evidence = evidence
      expect(decision).not_to be_valid
    end
    decision.evidence = {}
    decision.technical_details = { credits_consumed: 0, cost: 0, model: 'model' }
    expect(decision).to be_valid
    decision.settings_snapshot = { prompt: 'secret' }
    expect(decision).not_to be_valid
  end

  it 'rejects an account, assistant, anchor or parent from another scope' do
    decision.account = create(:account)
    expect(decision).not_to be_valid
    expect(decision.errors[:conversation]).to be_present
    expect(decision.errors[:assistant]).to be_present
    decision.account = account
    decision.anchor_message = create(:message)
    decision.parent_decision = create(:captain_decision)
    expect(decision).not_to be_valid
    expect(decision.errors[:anchor_message]).to be_present
    expect(decision.errors[:parent_decision]).to be_present
  end

  it 'rejects a same-account anchor and evidence message from another conversation' do
    message = create(:message, account: account)
    decision.anchor_message = message
    decision.evidence = { last_customer_message_id: message.id }
    expect(decision).not_to be_valid
    expect(decision.errors[:anchor_message]).to be_present
    expect(decision.errors[:evidence]).to be_present
  end

  it 'rejects a message reference from another account even if it has this conversation ID' do
    foreign_message = create(:message, account: create(:account), conversation: conversation)
    decision.evidence = { last_customer_message_id: foreign_message.id }
    expect(decision).not_to be_valid
    expect(decision.errors[:evidence]).to include('message references must belong to this conversation')
  end

  it 'requires a session for the same conversation, assistant and anchor' do
    message = create(:message, conversation: conversation, account: account)
    decision.anchor_message = message
    decision.agent_session = create(:captain_agent_session, assistant: assistant, subject: conversation, result: message)
    expect(decision).to be_valid
    decision.agent_session = create(:captain_agent_session, assistant: assistant, subject: create(:conversation, account: account))
    expect(decision).not_to be_valid
    expect(decision.errors[:agent_session]).to be_present
  end

  it 'rejects sources from another assistant and routing to another account' do
    document = create(:captain_document)
    decision.evidence = { document_ids: [document.id], team_id: create(:team).id, assignee_id: create(:user).id }
    expect(decision).not_to be_valid
    expect(decision.errors[:evidence]).to include('sources must belong to the decision assistant and account',
                                                  'routing must belong to the decision account')
  end

  it 'validates the combined JSON budget before reaching PostgreSQL' do
    decision.evidence = {
      tools: Array.new(50) { 'x' * 80 },
      document_ids: Array.new(100, 9_000_000_000_000_000_000), cited_document_ids: Array.new(100, 9_000_000_000_000_000_000),
      faq_ids: Array.new(100, 9_000_000_000_000_000_000)
    }
    expect(decision).not_to be_valid
    expect(decision.errors[:base]).to include('decision payload exceeds 8 KiB')
  end

  it 'includes PostgreSQL separator whitespace in the JSON size budget' do
    decision.evidence = {
      tools: Array.new(50) { 'x' * 80 }, document_ids: Array.new(100, 1_000_000_000),
      cited_document_ids: Array.new(100, 1_000_000_000), faq_ids: Array.new(100, 1_000_000_000), used_faq_ids: Array.new(26, 1_000_000_000)
    }
    encoded = described_class.connection.quote(decision.evidence.to_json)
    expect(described_class.connection.select_value("SELECT octet_length(#{encoded}::jsonb::text) + 4")).to eq(8200)
    expect(decision).not_to be_valid
    expect(decision.errors[:base]).to include('decision payload exceeds 8 KiB')
  end

  it 'enforces database checks even when validations are bypassed' do
    decision.save!
    [{ reason_text: 'x' * 501 }, { evidence: [] }, { settings_snapshot: [] }, { technical_details: [] },
     { evidence: { raw: 'x' * 8192 } }].each do |attributes|
      expect do
        described_class.transaction(requires_new: true) do
          decision.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations -- exercise PostgreSQL constraints
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it 'enforces an account-scoped unique execution key' do
    decision.save!
    duplicate = decision.dup
    expect(duplicate).not_to be_valid
    expect do
      described_class.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'cascades conversation deletion and nullifies deleted anchors' do
    decision.anchor_message = create(:message, conversation: conversation, account: account)
    decision.save!
    decision.anchor_message.delete
    expect(decision.reload.anchor_message_id).to be_nil
    conversation.delete
    expect(described_class.exists?(decision.id)).to be(false)
  end
end
