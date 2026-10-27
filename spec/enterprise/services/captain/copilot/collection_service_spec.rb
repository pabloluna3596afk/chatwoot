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

    it 'compares typed numeric attributes and sums them within a relative account-local month' do
      sales = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                                   attribute_display_type: 'currency', attribute_key: 'sales')
      first.update!(created_at: Time.zone.parse('2026-10-01 08:00:00'), custom_attributes: { sales.attribute_key => 12.5 })
      second.update!(created_at: Time.zone.parse('2026-10-21 08:00:00'), custom_attributes: { sales.attribute_key => 7.5 })
      create(:conversation, account: account, created_at: Time.zone.parse('2026-09-30 23:59:00'),
                            custom_attributes: { sales.attribute_key => 100 })
      travel_to Time.zone.parse('2026-10-27 12:00:00') do
        result = service.create(resource: 'conversations',
                                filters: { relative_range: 'this_month', custom_attribute: { key: 'sales', operator: 'gt', value: 0 } },
                                aggregate: { function: 'sum', key: 'sales' })

        expect(result[:total]).to eq(2)
        expect(result[:aggregate]).to eq({ function: 'sum', key: 'sales', value: BigDecimal(20) })
        last_month = service.create(resource: 'conversations', filters: { relative_range: 'last_month' },
                                    aggregate: { function: 'sum', key: 'sales' })
        expect(last_month[:aggregate][:value]).to eq(BigDecimal(100))
        expect(service.create(resource: 'conversations', filters: { relative_range: 'last_7_days' })[:total]).to eq(1)
      end
    end

    it 'supports numeric comparison operators and average, minimum, and maximum' do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'number', attribute_key: 'score')
      first.update!(custom_attributes: { score: 2 })
      second.update!(custom_attributes: { score: 8 })

      expect(service.create(
        resource: 'conversations', filters: { custom_attribute: { key: 'score', operator: 'between', values: [2, 8] } },
        aggregate: { function: 'avg', key: 'score' }
      )[:aggregate][:value]).to eq(BigDecimal(5))
      expect(service.create(resource: 'conversations', filters: { custom_attribute: { key: 'score', operator: 'gte', value: 8 } },
                            aggregate: { function: 'min', key: 'score' })[:aggregate][:value]).to eq(BigDecimal(8))
      expect(service.create(resource: 'conversations', filters: {}, aggregate: { function: 'max', key: 'score' })[:aggregate][:value])
        .to eq(BigDecimal(8))
    end

    it 'applies each numeric comparison operator to the declared numeric type' do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'number', attribute_key: 'score')
      first.update!(custom_attributes: { score: 2 })
      second.update!(custom_attributes: { score: 8 })
      cases = { 'eq' => [2, 1], 'neq' => [2, 1], 'gt' => [2, 1], 'gte' => [2, 2],
                'lt' => [8, 1], 'lte' => [8, 2], 'between' => [[2, 8], 2] }

      cases.each do |operator, (value, total)|
        attribute = { key: 'score', operator: operator }
        operator == 'between' ? attribute[:values] = value : attribute[:value] = value
        expect(service.create(resource: 'conversations', filters: { custom_attribute: attribute })[:total]).to eq(total)
      end
    end

    it 'supports text contains, boolean equality, and allowlisted list values' do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'text', attribute_key: 'segment')
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'checkbox', attribute_key: 'qualified')
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'list', attribute_key: 'tier', attribute_values: %w[gold silver])
      first.update!(custom_attributes: { segment: 'enterprise customer', qualified: true, tier: 'gold' })
      second.update!(custom_attributes: { segment: 'retail', qualified: false, tier: 'silver' })

      expect(service.create(resource: 'conversations',
                            filters: { custom_attribute: { key: 'segment', operator: 'contains', value: 'enterprise' } })[:total])
        .to eq(1)
      expect(service.create(resource: 'conversations', filters: { custom_attribute: { key: 'qualified', value: true } })[:total]).to eq(1)
      expect(service.create(resource: 'conversations', filters: { custom_attribute: { key: 'tier', value: 'gold' } })[:total]).to eq(1)
      expect do
        service.create(resource: 'conversations', filters: { custom_attribute: { key: 'tier', value: 'bronze' } })
      end.to raise_error(ArgumentError, /not an option/)
    end

    it 'validates and compares ISO date custom attributes' do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'date', attribute_key: 'renewal_date')
      first.update!(custom_attributes: { renewal_date: '2026-10-01' })
      second.update!(custom_attributes: { renewal_date: '2026-11-01' })

      result = service.create(resource: 'conversations',
                              filters: { custom_attribute: { key: 'renewal_date', operator: 'lt', value: '2026-10-15' } })

      expect(result[:total]).to eq(1)
      expect do
        service.create(resource: 'conversations', filters: { custom_attribute: { key: 'renewal_date', value: '10/15/2026' } })
      end.to raise_error(ArgumentError, /ISO 8601/)
    end

    it 'rejects unknown attributes, incompatible operators, and incorrectly typed values' do
      create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'text', attribute_key: 'segment')

      expect { service.create(resource: 'conversations', filters: { custom_attribute: { key: 'missing', operator: 'gt', value: 1 } }) }
        .to raise_error(ArgumentError, /Unknown conversation custom attribute key/)
      expect { service.create(resource: 'conversations', filters: { custom_attribute: { key: 'segment', operator: 'gt', value: 1 } }) }
        .to raise_error(ArgumentError, /not supported for text/)
      expect { service.create(resource: 'conversations', filters: { custom_attribute: { key: 'segment', value: 1 } }) }
        .to raise_error(ArgumentError, /values must be string/)
      expect { service.create(resource: 'conversations', filters: {}, aggregate: { function: 'sum', key: 'segment' }) }
        .to raise_error(ArgumentError, /requires a numeric custom attribute/)
    end

    it 'resolves yesterday and today to two local calendar days across reporting time zones' do
      travel_to Time.utc(2026, 11, 1, 4, 30) do
        new_york_account = create(:account, reporting_timezone: 'America/New_York')
        [Time.utc(2026, 10, 30, 17, 0), Time.utc(2026, 10, 31, 17, 0), Time.utc(2026, 11, 1, 4, 15)].each do |created_at|
          create(:conversation, account: account, created_at: created_at)
          create(:conversation, account: new_york_account, created_at: created_at)
        end

        guayaquil = service.create(resource: 'conversations', filters: { relative_range: 'yesterday_today' })
        new_york = described_class.new(account: new_york_account,
                                       user: create(:user, role: 'administrator', account: new_york_account))
                                  .create(resource: 'conversations', filters: { relative_range: 'yesterday_today' })

        expect(guayaquil[:total]).to eq(3)
        expect(new_york[:total]).to eq(2)
      end
    end

    it 'rejects ambiguous relative and explicit date ranges' do
      expect do
        service.create(resource: 'conversations', filters: { relative_range: 'this_month', since: '2026-10-01' })
      end.to raise_error(ArgumentError, /cannot be combined/)
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

  it 'sums a numeric contact attribute and keeps the contact label query account scoped' do
    contact = create(:contact, :with_email, account: account, contact_type: 'customer', custom_attributes: { sales: 5 })
    contact.add_labels(['vip'])
    create(:contact, :with_email, account: account, contact_type: 'customer', custom_attributes: { sales: 15 })
    create(:contact, :with_email, account: create(:account), contact_type: 'customer', custom_attributes: { sales: 100 })
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_display_type: 'currency', attribute_key: 'sales')

    result = service.create(
      resource: 'contacts', filters: { labels: ['vip'] }, aggregate: { function: 'sum', key: 'sales' }
    )

    expect(result[:total]).to eq(1)
    expect(result[:aggregate][:value]).to eq(BigDecimal(5))
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
