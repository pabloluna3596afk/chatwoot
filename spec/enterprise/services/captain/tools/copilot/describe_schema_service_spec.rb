require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::DescribeSchemaService do
  let(:account) { create(:account) }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  it 'describes standard fields and typed custom attributes with list options' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute',
                                                      attribute_display_type: 'list', attribute_key: 'segment',
                                                      attribute_display_name: 'Segment', attribute_values: %w[retail wholesale])

    result = service.execute(resource: 'conversations')

    expect(result[:standard_fields]).to include(hash_including(key: 'status', type: 'list'))
    expect(result[:custom_attributes]).to contain_exactly(
      hash_including(key: definition.attribute_key, name: 'Segment', type: 'list', values: %w[retail wholesale],
                     filter_operators: %w[eq neq is_null], aggregate_functions: [])
    )
    expect(result[:group_by]).to include('assignee')
  end

  it 'requires the matching CRM permission and scopes definitions to the assistant account' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    AccountUser.find_by!(account: account, user: user).update!(custom_role: role)
    create(:custom_attribute_definition, account: create(:account), attribute_model: 'conversation_attribute', attribute_key: 'secret')

    expect(service.execute(resource: 'contacts')).to include(error: 'You do not have permission to view contacts')
    expect(service.execute(resource: 'conversations')[:custom_attributes]).to be_empty
  end

  it 'returns an error for an unsupported resource' do
    expect(service.execute(resource: 'companies')).to include(error: 'resource must be conversations or contacts')
  end
end
