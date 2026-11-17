# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Automations::ProactiveSendCap do
  let(:account) { create(:account) }
  let(:cap) { described_class.new(account) }

  describe '#reserve! and #release!' do
    before { account.update!(settings: (account.settings || {}).merge('proactive_daily_send_cap' => 2)) }

    it 'takes places until the cap and refuses the next one without keeping it' do
      expect(cap.reserve!).to be(true)
      expect(cap.reserve!).to be(true)
      expect(cap.reserve!).to be(false)

      cap.release!
      expect(cap.reserve!).to be(true)
    end

    it 'isolates the reservation by account' do
      other_account = create(:account)
      account.update!(settings: { 'proactive_daily_send_cap' => 1 })
      expect(described_class.new(other_account).reserve!).to be(true)
      expect(cap.reserve!).to be(true)
    end
  end

  it 'releases a delayed reservation against its original day' do
    travel_to(Time.utc(2030, 1, 14, 15))
    original_date = Time.zone.today
    old = described_class.new(account)
    old.reserve!
    travel_to(Time.utc(2030, 1, 15, 15))
    today = described_class.new(account)
    today.reserve!
    described_class.new(account, date: original_date).release!
    account.update!(settings: { 'proactive_daily_send_cap' => 1 })
    expect(today.reserve!).to be(false)
    expect(old.reserve!).to be(true)
  ensure
    travel_back
  end
end
