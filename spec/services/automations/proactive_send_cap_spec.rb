# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Automations::ProactiveSendCap do
  let(:account) { create(:account) }
  let(:cap) { described_class.new(account) }

  describe '#within_cap?' do
    it 'is true below the default cap when nothing has been sent yet' do
      expect(cap.within_cap?).to be(true)
    end

    it 'is false once the configured cap has been reached' do
      account.update!(settings: (account.settings || {}).merge('proactive_daily_send_cap' => 2))

      cap.increment!
      cap.increment!

      expect(cap.within_cap?).to be(false)
    end

    it 'does not count sends from a different account' do
      other_account = create(:account)
      account.update!(settings: (account.settings || {}).merge('proactive_daily_send_cap' => 1))

      described_class.new(other_account).increment!

      expect(cap.within_cap?).to be(true)
    end
  end
end
