require 'rails_helper'

RSpec.describe Captain::FailureSpikeJob do
  let(:tracker) { instance_double(ChatwootExceptionTracker, capture_exception: nil) }

  before do
    freeze_time
    Redis::Alfred.delete("captain:failure_spike:#{Time.current.utc.strftime('%Y%m%d%H')}")
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
  end

  it 'reports when failures reach the threshold' do
    create_list(:conversation_outcome, 10, handoff_reason_category: 'tool_failure', handoff_at: 5.minutes.ago)

    described_class.perform_now

    expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(Captain::FailureSpikeError))
    expect(tracker).to have_received(:capture_exception).once
  end

  it 'stays silent below it' do
    create_list(:conversation_outcome, 9, handoff_reason_category: 'tool_failure', handoff_at: 5.minutes.ago)
    create(:conversation_outcome, handoff_reason_category: 'tool_failure', handoff_at: 61.minutes.ago)
    create(:conversation_outcome, handoff_reason_category: 'usage_limit', handoff_at: 5.minutes.ago)

    described_class.perform_now

    expect(tracker).not_to have_received(:capture_exception)
  end

  it 'reports once per hour' do
    create_list(:conversation_outcome, 10, handoff_reason_category: 'tool_failure', handoff_at: Time.current)

    2.times { described_class.perform_now }

    expect(tracker).to have_received(:capture_exception).once
    expect(Redis::Alfred.ttl("captain:failure_spike:#{Time.current.utc.strftime('%Y%m%d%H')}")).to be_between(7190, 7200)
  end

  it 'uses the configured installation threshold' do
    create(:installation_config, name: 'CAPTAIN_FAILURE_ALERT_THRESHOLD', value: 1)
    create(:conversation_outcome, handoff_reason_category: 'tool_failure', handoff_at: Time.current)

    described_class.perform_now

    expect(tracker).to have_received(:capture_exception).once
  end
end
