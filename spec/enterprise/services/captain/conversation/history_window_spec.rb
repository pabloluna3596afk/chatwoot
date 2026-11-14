require 'rails_helper'

RSpec.describe Captain::Conversation::HistoryWindow do
  subject(:result) { described_class.new(scope).perform }

  let(:conversation) { create(:conversation) }
  let(:scope) { conversation.messages.where(private: false, message_type: [:incoming, :outgoing, :activity]) }
  let(:attributes) do
    { account_id: conversation.account_id, inbox_id: conversation.inbox_id, conversation_id: conversation.id,
      message_type: :incoming, private: false, content: 'Context', created_at: 1.hour.ago, updated_at: 1.hour.ago }
  end
  let(:resolution_attributes) do
    attributes.merge(message_type: :activity, content_attributes: { activity: { type: 'conversation_status_changed', status: 'resolved' } })
  end

  it 'returns every message of a short conversation' do
    Message.create!([attributes] * 5)

    expect(result.messages.map(&:id)).to eq(scope.order(:created_at, :id).ids)
    expect(result.capped).to be false
  end

  it 'keeps only the last 40 messages of a long conversation without resolutions' do
    Message.create!([attributes] * 300)

    expect(result.messages.map(&:id)).to eq(scope.order(:id).last(40).map(&:id))
    expect(result.messages.size).to eq(40)
  end

  it 'keeps 10 messages before the last resolution marker and everything after it' do
    Message.create!(([attributes] * 20) + [resolution_attributes] + ([attributes] * 5))

    expect(result.messages.map(&:id)).to eq(scope.order(:id).last(16).map(&:id))
  end

  it 'uses the last resolution rather than an earlier one' do
    Message.create!([resolution_attributes] + ([attributes] * 20) + [resolution_attributes] + ([attributes] * 5))

    expect(result.messages.map(&:id)).to eq(scope.order(:id).last(16).map(&:id))
  end

  it 'still caps at 40 when the episode after the marker is longer' do
    Message.create!(([attributes] * 20) + [resolution_attributes] + ([attributes] * 50))

    expect(result.messages.map(&:id)).to eq(scope.order(:id).last(40).map(&:id))
  end

  it 'keeps the resolution marker inside the window' do
    Message.create!(([attributes] * 12) + [resolution_attributes] + ([attributes] * 5))

    expect(result.messages.count(&:activity?)).to eq(1)
  end

  it 'drops the marker when the current episode alone fills the window' do
    Message.create!([resolution_attributes] + ([attributes] * 40))

    expect(result.messages.size).to eq(40)
    expect(result.messages.none?(&:activity?)).to be true
  end

  it 'ignores activity messages that are not resolutions' do
    Message.create!([attributes, attributes.merge(message_type: :activity), resolution_attributes])

    expect(result.messages.map(&:id)).to eq([scope.order(:id).first.id, scope.order(:id).last.id])
  end

  it 'reads at most 200 messages' do
    Message.create!([attributes] * 300)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload if payload[:sql].include?('FROM "messages"') }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { result }

    loads = queries.select { |query| query[:sql].include?('SELECT "messages".*') }
    expect(loads.size).to eq(1)
    expect(loads.first[:sql]).to include('LIMIT')
    expect(loads.first[:binds].last.value_for_database).to eq(200)
    expect(result.messages.first.id).to eq(scope.order(:id).last(40).first.id)
    expect(described_class::LOOKBACK).to eq(200)
  end

  it 'preserves scope filters and preloads attachments' do
    Message.create!([attributes, attributes.merge(private: true)])

    expect(result.messages.size).to eq(1)
    expect(result.messages.first.association(:attachments)).to be_loaded
  end

  it 'lists the last 3 customer messages with images' do
    Message.create!(([attributes] * 6) + [attributes.merge(message_type: :outgoing)])
    scope.each do |message|
      message.attachments.create!(account_id: conversation.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
    end

    expect(result.image_message_ids).to eq(scope.incoming.order(:id).last(3).map(&:id))
  end

  it 'always contains the latest customer message' do
    Message.create!([attributes] + ([attributes.merge(message_type: :outgoing)] * 40))

    expect(result.messages.map(&:id)).to eq([scope.order(:id).first.id] + scope.order(:id).last(39).map(&:id))
    expect(result.messages.size).to eq(40)
  end

  it 'does not add an incoming message when none exists in the lookback' do
    Message.create!([attributes] + ([attributes.merge(message_type: :outgoing)] * 200))

    expect(result.messages.size).to eq(40)
    expect(result.messages.none?(&:incoming?)).to be true
  end

  it 'reports total and capped' do
    Message.create!([attributes] * 300)

    expect(result.total).to eq(300)
    expect(result.capped).to be true
  end

  it 'does not report capped when only non-resolution activities were dropped' do
    Message.create!([attributes, attributes.merge(message_type: :activity)])

    expect(result.total).to eq(2)
    expect(result.messages.size).to eq(1)
    expect(result.capped).to be false
  end

  it 'reports capped when the lookback drops older rows even if the window is short' do
    Message.create!([attributes] + ([attributes.merge(message_type: :activity)] * 200))

    expect(result.messages).to be_empty
    expect(result.total).to eq(201)
    expect(result.capped).to be true
  end
end
