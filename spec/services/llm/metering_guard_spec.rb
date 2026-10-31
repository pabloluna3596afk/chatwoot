require 'rails_helper'

RSpec.describe Llm::MeteringGuard do
  describe '.check!' do
    it 'rejects a provider call without an account usage context' do
      expect { described_class.check! }.to raise_error(Llm::UnmeteredCall, /missing context/)
    end

    it 'rejects a provider call with an unmapped feature in test' do
      account = create(:account)

      expect do
        Llm::UsageContext.with_instrumentation(account: account, feature_name: 'unreviewed_feature') do
          described_class.check!
        end
      end.to raise_error(Llm::UnmeteredCall, /Unmapped AI usage feature/)
    end

    it 'requires a reservation receipt when the context marks the call as limited' do
      account = create(:account)

      expect do
        Llm::UsageContext.with(account: account, feature: 'copilot', reservation_id: nil,
                               context: { reservation_required: true }) do
          described_class.check!
        end
      end.to raise_error(Llm::UnmeteredCall, /missing reservation receipt/)
    end

    it 'accepts a mapped, account-scoped and reserved call' do
      account = create(:account)
      usage = create_usage(account)
      reservation_id = SecureRandom.uuid
      AiUsageReservation.create!(account_plan_usage: usage, bucket: 'copilot', reservation_id: reservation_id)

      expect do
        Llm::UsageContext.with(account: account, feature: 'copilot', reservation_id: reservation_id,
                               context: { reservation_required: true }) do
          described_class.check!
        end
      end.not_to raise_error
    end

    it 'rejects a reservation receipt that is not active for the account and bucket' do
      account = create(:account)

      expect do
        Llm::UsageContext.with(account: account, feature: 'copilot', reservation_id: SecureRandom.uuid,
                               context: { reservation_required: true }) do
          described_class.check!
        end
      end.to raise_error(Llm::UnmeteredCall, /inactive reservation receipt/)
    end

    it 'records an unmapped event without interrupting production calls' do
      account = create(:account)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      ClimateControl.modify(CI: nil) do
        expect do
          Llm::UsageContext.with_instrumentation(account: account, feature_name: 'unreviewed_feature') do
            described_class.check!
            Llm::UsageContext.record_operation(model: 'gpt-6-luna', provider: 'openai', status: 'error')
          end
        end.to change { AiUsageEvent.where(account: account, feature: 'unreviewed_feature', bucket: 'unmapped').count }.by(1)
      end
    end
  end

  def create_usage(account)
    AccountPlanUsage.create!(
      account: account, period_start: Time.current.beginning_of_month,
      period_end: Time.current.end_of_month, limit_responses: 10
    )
  end
end
