# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account, type: :model do
  include ActiveJob::TestHelper

  describe 'associations' do
    it { is_expected.to have_many(:sla_policies).dependent(:destroy_async) }
    it { is_expected.to have_many(:applied_slas).dependent(:destroy_async) }
    it { is_expected.to have_many(:custom_roles).dependent(:destroy_async) }
  end

  describe '#selected_feature_flags=' do
    it 'keeps advanced assignment enabled when assignment v2 is selected for a business account' do
      account = build(:account, custom_attributes: { 'plan_name' => 'Business' })

      account.selected_feature_flags = [:feature_assignment_v2]

      expect(account).to be_feature_assignment_v2
      expect(account).to be_feature_advanced_assignment
    end

    it 'disables advanced assignment when assignment v2 is not selected' do
      account = build(:account, custom_attributes: { 'plan_name' => 'Business' })
      account.enable_features(:assignment_v2, :advanced_assignment)

      account.selected_feature_flags = []

      expect(account).not_to be_feature_assignment_v2
      expect(account).not_to be_feature_advanced_assignment
    end

    it 'uses Shopify plan features when preserving advanced assignment' do
      create(
        :installation_config,
        name: 'CHATWOOT_SHOPIFY_PLANS',
        value: [
          {
            'name' => 'Shopify Pro',
            'handle' => 'shopify-pro',
            'features' => %w[advanced_assignment],
            'limits' => { 'agents' => 10, 'inboxes' => 20 }
          }
        ],
        locked: true
      )
      account = build(
        :account,
        internal_attributes: { 'billing_provider' => 'shopify' },
        custom_attributes: { 'plan_name' => 'Shopify Pro' }
      )

      account.selected_feature_flags = [:feature_assignment_v2]

      expect(account).to be_feature_assignment_v2
      expect(account).to be_feature_advanced_assignment
    end
  end

  describe '#api_and_webhooks_enabled?' do
    let(:account) { create(:account) }

    it 'is always enabled for self-hosted enterprise accounts' do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
      account.disable_features!('api_and_webhooks')

      expect(account.api_and_webhooks_enabled?).to be true
    end

    it 'uses the account feature flag on Chatwoot Cloud' do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
      account.disable_features!('api_and_webhooks')

      expect(account.api_and_webhooks_enabled?).to be false

      account.enable_features!('api_and_webhooks')

      expect(account.api_and_webhooks_enabled?).to be true
    end
  end

  describe 'billing identity' do
    it 'defaults existing accounts to Stripe and Chatwoot signup' do
      account = create(:account)

      expect(account.billing_provider).to eq('stripe')
      expect(account.signup_source).to eq('chatwoot')
    end

    it 'stores Shopify identity at account creation' do
      account = create(
        :account,
        internal_attributes: {
          'billing_provider' => 'shopify',
          'signup_source' => 'shopify'
        }
      )

      expect(account.billing_provider).to eq('shopify')
      expect(account.signup_source).to eq('shopify')
    end

    it 'rejects unsupported billing providers and signup sources' do
      account = build(:account)
      account.billing_provider = 'unsupported'
      account.signup_source = 'unsupported'

      expect(account).not_to be_valid
      expect(account.errors[:billing_provider]).to be_present
      expect(account.errors[:signup_source]).to be_present
    end

    it 'does not allow billing identity to change after account creation' do
      account = create(:account)

      account.billing_provider = 'shopify'
      account.signup_source = 'shopify'

      expect(account.save).to be(false)
      expect(account.errors[:billing_provider]).to include('cannot be changed after account creation')
      expect(account.errors[:signup_source]).to include('cannot be changed after account creation')
      expect(account.reload.billing_provider).to eq('stripe')
      expect(account.signup_source).to eq('chatwoot')
    end

    it 'does not allow billing identity to change through symbol-keyed internal attributes' do
      account = create(:account)

      account.internal_attributes = account.internal_attributes.merge(billing_provider: 'shopify', signup_source: 'shopify')

      expect(account.save).to be(false)
      expect(account.errors[:billing_provider]).to include('cannot be changed after account creation')
      expect(account.errors[:signup_source]).to include('cannot be changed after account creation')
      expect(account.reload.billing_provider).to eq('stripe')
      expect(account.signup_source).to eq('chatwoot')
    end
  end

  describe 'sla_policies' do
    let!(:account) { create(:account) }
    let!(:sla_policy) { create(:sla_policy, account: account) }

    it 'returns associated sla policies' do
      expect(account.sla_policies).to eq([sla_policy])
    end

    it 'deletes associated sla policies' do
      perform_enqueued_jobs do
        account.destroy!
      end
      expect { sla_policy.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context 'with usage_limits' do
    let(:captain_limits) do
      {
        :startups => { :documents => 100, :responses => 100 },
        :business => { :documents => 200, :responses => 300 },
        :enterprise => { :documents => 300, :responses => 500 }
      }.with_indifferent_access
    end
    let(:account) { create(:account, { custom_attributes: { plan_name: 'startups' } }) }
    let(:assistant) { create(:captain_assistant, account: account) }

    before do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
      create(:installation_config, name: 'ACCOUNT_AGENTS_LIMIT', value: 20)
    end

    # Captain quotas come from the plan and its usage period (AccountPlanUsage); an account with no plan is
    # neither metered nor limited.
    describe 'when the account has no plan' do
      it 'is not limited and is not metered' do
        account.increment_response_usage

        expect(account.usage_limits[:captain][:responses]).to include(total_count: ChatwootApp.max_limit, consumed: 0)
        expect(account.usage_limits[:captain][:documents]).to include(total_count: ChatwootApp.max_limit, consumed: 0)
      end
    end

    describe 'when the account is on a plan' do
      before { put_account_on_plan(account, monthly_messages: 100, max_documents: 50) }

      it 'counts the responses of the current period against the plan' do
        account.increment_response_usage

        expect(account.usage_limits[:captain][:responses]).to include(total_count: 100, consumed: 1, current_available: 99)
      end

      it 'counts Copilot responses apart from the customer ones' do
        account.increment_response_usage(source: :copilot)

        expect(copilot_responses_used(account)).to eq(1)
        expect(captain_responses_used(account)).to eq(0)
      end

      it 'keeps current_available inside its bounds' do
        account.current_usage_period.update!(responses_consumed: 3000)

        expect(account.usage_limits[:captain][:responses]).to include(consumed: 3000, current_available: 0)
      end

      it 'starts a fresh period when the usage is reset' do
        account.current_usage_period.update!(responses_consumed: 30)
        expect(account.usage_limits[:captain][:responses]).to include(consumed: 30, current_available: 70)

        account.reset_response_usage

        expect(account.usage_limits[:captain][:responses]).to include(consumed: 0, current_available: 100)
      end

      it 'counts the documents of the account against the plan' do
        create_list(:captain_document, 3, account: account, assistant: assistant, status: :available)

        account.update_document_usage

        expect(account.usage_limits[:captain][:documents]).to include(total_count: 50, consumed: 3, current_available: 47)
      end

      it 'lets the limits of the account override the plan' do
        account.update!(limits: { 'captain_responses' => 9999 })

        expect(account.usage_limits[:captain][:responses][:total_count]).to eq(9999)
      end
    end

    describe 'when limits are configured for an account' do
      before do
        create(:installation_config, name: 'CAPTAIN_CLOUD_PLAN_LIMITS', value: captain_limits.to_json)
        account.update(limits: { captain_documents: 5555, captain_responses: 9999 })
      end

      it 'returns limits based on custom attributes' do
        usage_limits = account.usage_limits
        expect(usage_limits[:captain][:documents][:total_count]).to eq(5555)
        expect(usage_limits[:captain][:responses][:total_count]).to eq(9999)
      end
    end

    describe 'audit logs' do
      it 'returns audit logs' do
        # checking whether associated_audits method is present
        expect(account.associated_audits.present?).to be false
      end

      it 'creates audit logs when account is updated' do
        account.update(name: 'New Name')
        expect(Audited::Audit.where(auditable_type: 'Account', action: 'update').count).to eq 1
      end
    end

    it 'returns max limits from global config when enterprise version' do
      expect(account.usage_limits[:agents]).to eq(20)
    end

    it 'returns max limits from account when enterprise version' do
      account.update(limits: { agents: 10 })
      expect(account.usage_limits[:agents]).to eq(10)
    end

    it 'returns limits based on subscription' do
      account.update(limits: { agents: 10 }, custom_attributes: { subscribed_quantity: 5 })
      expect(account.usage_limits[:agents]).to eq(5)
    end

    it 'returns max limits from global config if account limit is absent' do
      account.update(limits: { agents: '' })
      expect(account.usage_limits[:agents]).to eq(20)
    end

    it 'returns max limits from app limit if account limit and installation config is absent' do
      account.update(limits: { agents: '' })
      InstallationConfig.where(name: 'ACCOUNT_AGENTS_LIMIT').update(value: '')

      expect(account.usage_limits[:agents]).to eq(ChatwootApp.max_limit)
    end
  end

  context 'with Shopify plan entitlements' do
    let(:account) do
      create(
        :account,
        internal_attributes: { 'billing_provider' => 'shopify' },
        custom_attributes: {
          'plan_name' => 'Shopify Basic',
          'subscribed_quantity' => 100,
          'captain_documents_usage' => 5,
          'captain_responses_usage' => 10
        }
      )
    end
    let(:shopify_plan) do
      {
        'name' => 'Shopify Basic',
        'handle' => 'shopify-basic',
        'features' => %w[help_center campaigns],
        'limits' => {
          'agents' => 5,
          'inboxes' => 10,
          'emails' => 500,
          'captain_documents' => 25,
          'captain_responses' => 100
        }
      }
    end

    before do
      create(:installation_config, name: 'CHATWOOT_SHOPIFY_PLANS', value: [shopify_plan], locked: true)
    end

    it 'uses fixed Shopify limits instead of Stripe subscription quantity or global limits' do
      usage_limits = account.usage_limits

      expect(usage_limits[:agents]).to eq(5)
      expect(usage_limits[:inboxes]).to eq(10)
      expect(usage_limits.dig(:captain, :documents)).to eq(
        total_count: 25,
        current_available: 20,
        consumed: 5
      )
      expect(usage_limits.dig(:captain, :responses)).to eq(
        total_count: 100,
        current_available: 90,
        consumed: 10
      )
      expect(account.email_rate_limit).to eq(500)
    end

    it 'reads subscribed features from the Shopify plan catalog' do
      expect(account.subscribed_features).to eq(%w[help_center campaigns])
      expect(account.email_transcript_enabled?).to be(true)
    end

    it 'fails closed when the stored Shopify plan is unknown' do
      account.update!(custom_attributes: { 'plan_name' => 'Unknown' })

      expect(account.usage_limits[:agents]).to eq(0)
      expect(account.usage_limits[:inboxes]).to eq(0)
      expect(account.subscribed_features).to eq([])
      expect(account.email_transcript_enabled?).to be(false)
    end
  end

  describe 'subscribed_features' do
    let(:account) { create(:account) }
    let(:plan_features) do
      {
        'hacker' => %w[feature1 feature2],
        'startups' => %w[feature1 feature2 feature3 feature4]
      }
    end

    before do
      InstallationConfig.where(name: 'CHATWOOT_CLOUD_PLAN_FEATURES').first_or_create(value: plan_features)
    end

    context 'when plan_name is hacker' do
      it 'returns the features for the hacker plan' do
        put_account_on_plan(account, slug: 'hacker')

        expect(account.subscribed_features).to eq(%w[feature1 feature2])
      end
    end

    context 'when plan_name is startups' do
      it 'returns the features for the startups plan' do
        put_account_on_plan(account, slug: 'startups')

        expect(account.subscribed_features).to eq(%w[feature1 feature2 feature3 feature4])
      end
    end

    context 'when plan_features is blank' do
      it 'returns an empty array' do
        account.custom_attributes = {}
        account.save!

        expect(account.subscribed_features).to be_nil
      end
    end
  end

  describe 'default features' do
    before do
      InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(
        value: Featurable::FEATURE_LIST,
        locked: true
      )
    end

    it 'enables Captain V2 for new paid self-hosted accounts' do
      allow(ChatwootApp).to receive(:self_hosted_paid?).and_return(true)

      account = create(:account)

      expect(account).to be_feature_enabled('captain_integration')
      expect(account).to be_feature_enabled('captain_integration_v2')
      expect(account.captain_preferences[:models]['assistant']).to eq('gpt-5.2')
      expect(account.captain_models).to be_nil
    end
  end

  describe 'captain document sync cadence' do
    let(:account) { create(:account) }

    it 'has no cadence when installation config is missing' do
      account.update!(custom_attributes: { plan_name: 'business' })
      expect(account.captain_document_sync_interval).to be_nil
    end

    it 'uses configured plan intervals from installation config' do
      intervals = {
        business: 48,
        enterprise: 24
      }
      create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: intervals.to_json)
      account.update!(custom_attributes: { plan_name: 'business' })

      expect(account.captain_document_sync_interval).to eq(2.days)
    end

    it 'normalizes configured plan name casing' do
      create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: { business: 24 }.to_json)
      account.update!(custom_attributes: { plan_name: 'Business' })

      expect(account.captain_document_sync_interval).to eq(1.day)
    end

    it 'uses the enterprise cadence for paid self-hosted installs without a plan_name' do
      allow(ChatwootApp).to receive(:self_hosted_paid?).and_return(true)
      create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: { enterprise: 6 }.to_json)
      account.update!(custom_attributes: {})

      expect(account.captain_document_sync_interval).to eq(6.hours)
    end

    it 'allows installation config to disable a plan cadence' do
      create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: { business: nil }.to_json)
      account.update!(custom_attributes: { plan_name: 'business' })

      expect(account.captain_document_sync_interval).to be_nil
    end

    it 'has no cadence when installation config is invalid' do
      create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: 'invalid-json')
      account.update!(custom_attributes: { plan_name: 'business' })

      expect(account.captain_document_sync_interval).to be_nil
    end

    it 'treats invalid plan interval values as disabled' do
      intervals = {
        business: false,
        enterprise: { hours: 6 },
        startups: '168'
      }
      create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: intervals.to_json)

      account.update!(custom_attributes: { plan_name: 'business' })
      expect(account.captain_document_sync_interval).to be_nil

      account.update!(custom_attributes: { plan_name: 'enterprise' })
      expect(account.captain_document_sync_interval).to be_nil

      account.update!(custom_attributes: { plan_name: 'startups' })
      expect(account.captain_document_sync_interval).to be_nil
    end
  end

  describe 'account deletion' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }

    describe '#mark_for_deletion' do
      it 'sets the marked_for_deletion_at and marked_for_deletion_reason attributes' do
        expect do
          account.mark_for_deletion('inactivity')
        end.to change { account.reload.custom_attributes['marked_for_deletion_at'] }.from(nil).to(be_present)
           .and change { account.reload.custom_attributes['marked_for_deletion_reason'] }.from(nil).to('inactivity')
      end

      it 'sends a user-initiated deletion email when reason is manual_deletion' do
        mailer = double
        expect(AdministratorNotifications::AccountNotificationMailer).to receive(:with).with(account: account).and_return(mailer)
        expect(mailer).to receive(:account_deletion_user_initiated).with(account, 'manual_deletion').and_return(mailer)
        expect(mailer).to receive(:deliver_later)

        account.mark_for_deletion('manual_deletion')
      end

      it 'sends a system-initiated deletion email when reason is not manual_deletion' do
        mailer = double
        expect(AdministratorNotifications::AccountNotificationMailer).to receive(:with).with(account: account).and_return(mailer)
        expect(mailer).to receive(:account_deletion_for_inactivity).with(account, 'inactivity').and_return(mailer)
        expect(mailer).to receive(:deliver_later)

        account.mark_for_deletion('inactivity')
      end

      it 'returns true when successful' do
        expect(account.mark_for_deletion).to be_truthy
      end
    end

    describe '#unmark_for_deletion' do
      before do
        account.update!(
          custom_attributes: {
            'marked_for_deletion_at' => 7.days.from_now.iso8601,
            'marked_for_deletion_reason' => 'test_reason'
          }
        )
      end

      it 'removes the marked_for_deletion_at and marked_for_deletion_reason attributes' do
        expect do
          account.unmark_for_deletion
        end.to change { account.reload.custom_attributes['marked_for_deletion_at'] }.from(be_present).to(nil)
           .and change { account.reload.custom_attributes['marked_for_deletion_reason'] }.from('test_reason').to(nil)
      end

      it 'returns true when successful' do
        expect(account.unmark_for_deletion).to be_truthy
      end
    end
  end
end
