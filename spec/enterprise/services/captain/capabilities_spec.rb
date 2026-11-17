require 'rails_helper'

RSpec.describe Captain::Capabilities do
  let(:calendar_connections) do
    instance_double(ActiveRecord::Associations::CollectionProxy,
                    active: instance_double(ActiveRecord::Associations::CollectionProxy, exists?: false))
  end
  let(:account) { instance_double(Account, calendar_connections: calendar_connections) }
  let(:captain_inboxes) { instance_double(ActiveRecord::Associations::CollectionProxy, includes: []) }
  let(:assistant) do
    instance_double(
      Captain::Assistant,
      id: 19,
      config: {},
      account: account,
      captain_inboxes: captain_inboxes,
      appointments: instance_double(Captain::AppointmentsSettings, enabled?: false),
      followup: instance_double(Captain::FollowupSettings, inactivity_enabled?: true, max_nudges: 1)
    )
  end

  it 'returns the three groups and six ordered rows for an assistant without integrations' do
    result = described_class.new(assistant).to_h
    groups = result.fetch(:groups)

    expect(groups.pluck(:id)).to eq(%w[whatsapp calendar none])
    expect(groups.pluck(:connection)).to eq(%w[not_connected not_connected always])
    expect(groups.flat_map { |group| group.fetch(:items) }.pluck(:id)).to eq(
      %w[allowed_templates allowed_flows reengagement booking appointment_reminders nudge]
    )
    expect(groups.flat_map { |group| group.fetch(:items) }.pluck(:status)).to eq(
      %w[not_connected not_connected not_connected not_connected not_connected ready]
    )
  end

  it 'omits a failing capability row and still returns the other rows' do
    allow(Captain::Capabilities::Nudge).to receive(:new).and_raise(StandardError, 'test failure')

    groups = described_class.new(assistant).to_h.fetch(:groups)

    expect(groups.flat_map { |group| group.fetch(:items) }.pluck(:id)).not_to include('nudge')
    expect(groups.flat_map { |group| group.fetch(:items) }.length).to eq(5)
  end
end
