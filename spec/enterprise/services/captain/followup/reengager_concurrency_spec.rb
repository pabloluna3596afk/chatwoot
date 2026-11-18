require 'rails_helper'

RSpec.describe Captain::Followup::Reengager do
  self.use_transactional_tests = false
  include_context 'with an empty database after the example'

  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:now) { Time.use_zone(account.reporting_timezone) { Time.zone.parse('2030-01-15 10:00:00') } }

  around { |example| travel_to(now) { example.run } }

  it 'serializes the cooldown across two conversations of the same contact' do
    conversations = Array.new(2) do
      create(:conversation, account: account, contact: contact, status: :resolved,
                            additional_attributes: { 'captain_followup' => { 'closed_at' => (now - 2.days).utc.iso8601 } })
    end
    conversations.each(&:reload)
    senders = conversations.map { |conversation| described_class.new(conversation, assistant, now: now) }
    entered = Queue.new
    release = Queue.new
    allow(conversations.first).to receive(:can_reply?).and_return(false)
    allow(conversations.last).to receive(:can_reply?).and_return(false)
    # Hold the first delivery after eligibility. Another worker must wait before checking cooldown.
    allow(senders.first).to receive(:deliver).and_wrap_original do |_original|
      entered << true
      release.pop
      attributes = conversations.first.additional_attributes.deep_dup
      attributes['captain_followup']['reengagement'] = { 'status' => 'sent', 'at' => now.utc.iso8601 }
      conversations.first.update!(additional_attributes: attributes)
      :sent
    end
    first = Thread.new { ActiveRecord::Base.connection_pool.with_connection { senders.first.perform } }
    Timeout.timeout(10) { entered.pop }
    second = Thread.new { ActiveRecord::Base.connection_pool.with_connection { senders.last.perform } }
    # Wait for PostgreSQL to confirm contention, rather than assuming thread scheduling.
    Timeout.timeout(10) do
      loop do
        break if ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted").positive?

        Thread.pass
      end
    end
    release << true
    expect(first.value).to eq(:sent)
    expect(second.value).to eq(:skipped)
    expect(conversations.last.reload.additional_attributes.dig('captain_followup', 'reengagement', 'reason')).to eq('cooldown')
  ensure
    [first, second].compact.each { |thread| thread.kill if thread.alive? }
  end
end
