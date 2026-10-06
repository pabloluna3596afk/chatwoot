require 'rails_helper'

RSpec.describe WhatsappFlowPublication do
  let(:flow) { create(:whatsapp_flow) }
  let(:attributes) { { whatsapp_flow_id: flow.id, account_id: flow.account_id, waba_id: '123456789' } }

  it 'starts as a draft with no errors and no version' do
    publication = described_class.create!(attributes)

    expect(publication).to have_attributes(status: 'draft', validation_errors: [], published_version: 0, meta_flow_id: nil)
    expect(publication.validation_errors?).to be false
    expect(publication.published_in_meta?).to be false
  end

  it 'only takes the statuses Meta has' do
    expect(described_class.new(attributes.merge(status: 'published'))).to be_valid
    expect(described_class.new(attributes.merge(status: 'approved'))).not_to be_valid
  end

  it 'needs a numeric WABA id' do
    expect(described_class.new(attributes.merge(waba_id: 'abc'))).not_to be_valid
    expect(described_class.new(attributes.merge(waba_id: ''))).not_to be_valid
  end

  it 'has one row per flow and WABA' do
    described_class.create!(attributes)

    expect(described_class.new(attributes)).not_to be_valid
    expect(described_class.new(attributes.merge(waba_id: '987654321'))).to be_valid
  end

  it 'finds the ones with errors' do
    clean = described_class.create!(attributes)
    broken = described_class.create!(attributes.merge(waba_id: '987654321', validation_errors: [{ 'error' => 'X' }]))

    expect(described_class.with_errors).to contain_exactly(broken)
    expect(described_class.with_errors).not_to include(clean)
  end

  it 'goes away with its flow' do
    described_class.create!(attributes)

    expect { flow.destroy! }.to change(described_class, :count).by(-1)
  end
end
