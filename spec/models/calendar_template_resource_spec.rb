require 'rails_helper'

RSpec.describe CalendarTemplateResource do
  let(:account) { create(:account) }
  let(:resource) { described_class.new(account: account, function: :confirmation, language: 'es', template_name: 'cita_confirmacion') }

  it 'allows local preparation without a WABA, remote identity or draft' do
    expect(resource.save!).to be(true)
    expect(resource.reload).to have_attributes(status: 'pending', waba_id: nil, contract_snapshot: {})
  end

  it 'requires a supported language and a template name' do
    resource.assign_attributes(language: 'fr', template_name: nil)
    expect(resource).not_to be_valid
    expect(resource.errors.attribute_names).to include(:language, :template_name)
  end

  it 'rejects linked resources without an identity, time and contract' do
    resource.status = :linked
    expect(resource).not_to be_valid
    expect(resource.errors.attribute_names).to include(:waba_id, :remote_template_id, :linked_at, :contract_snapshot)
  end

  [nil, 'waba-1'].each do |waba|
    it "enforces the identity in validations and PostgreSQL with WABA #{waba.inspect}" do
      resource.update!(waba_id: waba)
      duplicate = resource.dup
      expect(duplicate).not_to be_valid
      expect do
        described_class.transaction(requires_new: true) { duplicate.save!(validate: false) }
      end.to raise_error(ActiveRecord::RecordNotUnique) { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotUnique') }
    end
  end

  it 'keeps functions, accounts, languages and WABAs independent' do
    resource.save!
    expect(resource.dup.tap { |other| other.function = :reminder }).to be_valid
    expect(resource.dup.tap { |other| other.account = create(:account) }).to be_valid
    expect(resource.dup.tap { |other| other.language = 'en' }).to be_valid
    expect(resource.dup.tap { |other| other.waba_id = 'waba-2' }).to be_valid
  end

  it 'rejects drafts belonging to another account or destination' do
    resource.whatsapp_template_draft = create(:whatsapp_template_draft)
    expect(resource).not_to be_valid
    expect(resource.errors[:whatsapp_template_draft]).to be_present

    resource.whatsapp_template_draft = create(:whatsapp_template_draft, account: account)
    resource.waba_id = 'different-waba'
    expect(resource).not_to be_valid
    expect(resource.errors[:whatsapp_template_draft]).to be_present
  end
end
