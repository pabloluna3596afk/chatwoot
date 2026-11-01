require 'rails_helper'

RSpec.describe Payphone::BillingLifecycle do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:plan) { Plan.create!(name: 'Growth', slug: 'growth', price_monthly: 149, is_active: true, is_public: true) }
  let(:free_plan) { Plan.create!(name: 'Gratis', slug: 'gratis', price_monthly: 0, is_active: true, is_public: true) }
  let(:period_end) { Time.zone.parse('2026-11-20 18:00:00') }
  let(:payment) do
    PayphonePayment.create!(account: account, user: user, plan: plan, client_transaction_id: SecureRandom.uuid,
                            amount: 100, amount_without_tax: 100, amount_with_tax: 0, tax: 0,
                            base_cents: 100, tax_cents: 0, commission_cents: 0).tap do |record|
      record.transition_to!('approved', attributes: {
                              paid_at: period_end - 30.days, period_start: period_end - 30.days,
                              period_end: period_end, confirmed_at: period_end - 30.days
                            })
    end
  end
  let(:delivery) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }
  let(:mailer) { instance_double(PayphoneBillingMailer, notice: delivery) }

  before do
    free_plan
    account.update!(plan: plan, plan_started_at: payment.period_start)
    allow(PayphoneBillingMailer).to receive(:with).and_return(mailer)
  end

  it 'sends the 7, 3, and 1 day reminders once using Guayaquil calendar dates' do
    [7, 3, 1].each do |days|
      travel_to(period_end - days.days + 2.hours) do
        described_class.call
        described_class.call
      end
    end

    reminders = payment.reload.status_history.filter_map { |entry| entry['event'] if entry['event']&.start_with?('renewal_reminder_') }
    expect(reminders).to contain_exactly('renewal_reminder_7', 'renewal_reminder_3', 'renewal_reminder_1')
    expect(PayphoneBillingMailer).to have_received(:with).exactly(3).times
  end

  it 'keeps the paid plan during the three-day grace period and downgrades once afterward' do
    travel_to(period_end + 1.day) do
      described_class.call
      expect(account.reload.plan_id).to eq(plan.id)
      expect(payment.reload.status_history.map { |entry| entry['event'] }).to include('grace_started')
    end

    travel_to(period_end + 3.days - 1.minute) do
      described_class.call
      expect(account.reload.plan_id).to eq(plan.id)
    end

    travel_to(period_end + 3.days) do
      described_class.call
      described_class.call
      expect(account.reload.plan_id).to eq(free_plan.id)
      expect(account.current_usage_period.plan_id).to eq(free_plan.id)
      expect(payment.reload.status_history.map { |entry| entry['event'] }).to include('downgraded_to_free')
      expect(PayphoneBillingMailer).to have_received(:with).with(payment: payment, event: 'downgraded_to_free').once
    end
  end
end
