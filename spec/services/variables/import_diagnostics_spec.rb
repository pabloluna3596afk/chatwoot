require 'rails_helper'

RSpec.describe Variables::ImportDiagnostics do
  let(:data_import) { create(:data_import) }
  let(:account) { data_import.account }
  let(:diagnostics) { described_class.new(data_import: data_import) }

  it 'reports only undefined keys, never values, and merges repeated batches into one warning per scope' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'known')
    diagnostics.check(scope: 'contact', values: { known: 'ok', hidden: 'SECRET' })
    diagnostics.check(scope: 'contact', values: { hidden: 'SECRET', another: 0 })
    diagnostics.check(scope: 'contact', values: { hidden: false })

    expect(data_import.import_errors.count).to eq(1)
    warning = data_import.import_errors.first
    expect(warning.details).to eq('kind' => 'warning', 'keys' => %w[another hidden])
    expect(warning.message).to include('another, hidden')
    expect(warning.message).not_to include('SECRET')
  end

  it 'does not create a warning for defined attributes or promote source metadata into definitions' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'known')
    diagnostics.check(scope: 'contact', values: { known: 'ok' })

    expect(data_import.import_errors).to be_empty
    expect(account.custom_attribute_definitions.count).to eq(1)
  end

  it 'does not use definitions from another account or scope' do
    create(:custom_attribute_definition, attribute_model: 'contact_attribute', attribute_key: 'other_account')
    create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute', attribute_key: 'other_scope')
    diagnostics.check(scope: 'contact', values: { other_account: 'x', other_scope: 'y' })

    expect(data_import.import_errors.first.details['keys']).to eq(%w[other_account other_scope])
  end
end
