require 'rails_helper'

RSpec.describe Captain::Capabilities::Nudge do
  let(:followup) { instance_double(Captain::FollowupSettings, inactivity_enabled?: enabled, max_nudges: max_nudges) }
  let(:assistant) { instance_double(Captain::Assistant, followup: followup) }
  let(:enabled) { true }
  let(:max_nudges) { 1 }

  it 'returns ready when nudges are enabled and the count is positive' do
    expect(described_class.new(assistant).call).to eq(status: 'ready', reason: nil, count: nil)
  end

  it 'returns off when nudges are disabled or the count is zero' do
    allow(followup).to receive(:inactivity_enabled?).and_return(false)
    expect(described_class.new(assistant).call).to eq(status: 'off', reason: 'disabled', count: nil)

    allow(followup).to receive(:inactivity_enabled?).and_return(true)
    allow(followup).to receive(:max_nudges).and_return(0)
    expect(described_class.new(assistant).call).to eq(status: 'off', reason: 'disabled', count: nil)
  end
end
