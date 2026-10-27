require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::ListCustomAttributesService do
  let(:account) { create(:account) }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'lists keys and display names for the requested resource' do
    definition = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                                      attribute_key: 'region', attribute_display_name: 'Region')

    expect(described_class.new(assistant, user: user).execute(resource: 'contacts')).to contain_exactly(
      hash_including(key: definition.attribute_key, name: definition.attribute_display_name)
    )
    expect(described_class.new(assistant, user: user).execute(resource: 'conversations')).to be_empty
  end

  it 'returns a clear error for an unsupported resource' do
    expect(described_class.new(assistant, user: user).execute(resource: 'companies'))
      .to include(error: 'resource must be conversations or contacts')
  end
end
