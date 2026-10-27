require 'rails_helper'

RSpec.describe Captain::Copilot::CollectionService do
  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:service) { described_class.new(account: account, user: user) }

  describe '#create' do
    let!(:first) { create(:conversation, account: account, created_at: Time.zone.parse('2026-10-20 12:00:00')) }
    let!(:second) { create(:conversation, account: account, created_at: Time.zone.parse('2026-10-21 12:00:00')) }

    it 'returns exact counts and groups without record bodies' do
      expect([first, second].size).to eq(2)
      result = service.create(resource: 'conversations', filters: {}, group_by: 'status')

      expect(result[:total]).to eq(2)
      expect(result[:groups]).to contain_exactly({ group: 'open', count: 2 })
      expect(result.keys).not_to include(:records, :messages, :body)
    end

    it 'counts new conversations in a date range in the account timezone' do
      result = service.create(
        resource: 'conversations',
        filters: { since: '2026-10-20T00:00:00-05:00', before: '2026-10-21T00:00:00-05:00', date_field: 'created_at' }
      )

      expect(result[:total]).to eq(1)
    end

    it 'filters on validated conversation custom attributes' do
      definition = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                                        attribute_display_type: 'text', attribute_key: 'segment')
      first.update!(custom_attributes: { definition.attribute_key => 'premium' })

      result = service.create(resource: 'conversations', filters: { custom_attribute: { key: 'segment', value: 'premium' } })

      expect(result[:total]).to eq(1)
    end

    it 'rejects unknown custom attribute keys' do
      expect do
        service.create(resource: 'conversations', filters: { custom_attribute: { key: 'missing', value: 'x' } })
      end.to raise_error(ArgumentError, /Unknown conversation custom attribute key/)
    end

    it 'rejects date ranges longer than one year' do
      expect do
        service.create(resource: 'conversations', filters: { since: '2024-01-01T00:00:00Z', before: '2026-01-01T00:00:00Z' })
      end.to raise_error(ArgumentError, /cannot exceed/)
    end

    it 'requires a bounded date range when a before date is supplied' do
      expect do
        service.create(resource: 'conversations', filters: { before: '2026-10-21T00:00:00Z' })
      end.to raise_error(ArgumentError, 'since is required when before is provided')
    end

    it 'rejects unsupported grouping and filters' do
      expect { service.create(resource: 'conversations', filters: {}, group_by: 'customer_email') }
        .to raise_error(ArgumentError, /group_by must be one of/)
      expect { service.create(resource: 'conversations', filters: { unknown: 'x' }) }
        .to raise_error(ArgumentError, /Invalid conversations filters/)
      expect { service.create(resource: 'conversations', filters: {}, group_by: '') }
        .to raise_error(ArgumentError, /group_by must be one of/)
    end
  end

  it 'counts contacts only with contact permission and isolates account scope' do
    contact = create(:contact, :with_email, account: account, contact_type: 'customer')
    create(:contact, account: create(:account))

    expect(service.create(resource: 'contacts', filters: {})[:total]).to eq(1)
    contact.update!(custom_attributes: { 'region' => 'north' })
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_display_type: 'text', attribute_key: 'region')
    expect(service.create(resource: 'contacts', filters: { custom_attribute: { key: 'region', value: 'north' } })[:total]).to eq(1)
  end

  it 'filters contacts by labels and groups them by label' do
    contact = create(:contact, :with_email, account: account, contact_type: 'customer')
    contact.add_labels(['vip'])

    result = service.create(resource: 'contacts', filters: { labels: ['vip'] }, group_by: 'label')

    expect(result[:total]).to eq(1)
    expect(result[:groups]).to contain_exactly({ group: 'vip', count: 1 })
  end

  it 'keeps never-active contacts in counts without a date range' do
    create(:contact, :with_email, account: account, last_activity_at: nil)

    result = service.create(resource: 'contacts', filters: { date_field: 'last_activity_at' })

    expect(result[:total]).to eq(1)
  end

  it 'limits conversation counts to the agent inbox permissions' do
    agent = create(:user, role: 'agent', account: account)
    assigned_inbox = create(:inbox, account: account, channel: create(:channel_widget, account: account))
    other_inbox = create(:inbox, account: account, channel: create(:channel_widget, account: account))
    create(:conversation, account: account, inbox: assigned_inbox)
    create(:conversation, account: account, inbox: other_inbox)
    agent.inboxes << assigned_inbox

    result = described_class.new(account: account, user: agent).create(resource: 'conversations', filters: {})

    expect(result[:total]).to eq(1)
  end

  it 'denies contacts to a custom role without contact_manage' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    AccountUser.find_by!(account: account, user: user).update!(custom_role: role)

    expect { service.create(resource: 'contacts', filters: {}) }
      .to raise_error(ArgumentError, 'You do not have permission to view contacts')
  end

  it 'rejects groups beyond the configured maximum' do
    resource = Captain::Copilot::Resources.build('contacts', account: account, user: user)
    allow(resource).to receive(:counts_by).and_return((1..101).index_with { |_number| 1 })

    expect { resource.group_counts(Contact.none, 'label') }
      .to raise_error(ArgumentError, /produces more than 100 groups/)
  end
end
