require 'rails_helper'

RSpec.describe WhatsappFlow do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
  end

  describe 'validations' do
    it 'needs a name of up to 100 characters' do
      expect(build(:whatsapp_flow, name: ' ')).not_to be_valid
      expect(build(:whatsapp_flow, name: 'a' * 101)).not_to be_valid
      expect(build(:whatsapp_flow, name: 'a' * 100)).to be_valid
    end

    it 'only takes the categories of Meta' do
      expect(build(:whatsapp_flow, categories: %w[SURVEY CONTACT_US])).to be_valid
      expect(build(:whatsapp_flow, categories: %w[SURVEY INVENTADA])).not_to be_valid
    end

    it 'needs a definition with a list of screens, and not too big a one' do
      expect(build(:whatsapp_flow, definition: { 'screens' => 'x' })).not_to be_valid
      expect(build(:whatsapp_flow, definition: { 'screens' => [] })).to be_valid
      huge = { 'screens' => [{ 'title' => 'x' * (described_class::MAX_DEFINITION_BYTES + 1) }] }
      expect(build(:whatsapp_flow, definition: huge)).not_to be_valid
    end
  end

  describe 'normalizing' do
    it 'trims the name, drops repeated categories, uses string keys and marks the schema version' do
      flow = create(:whatsapp_flow, name: '  Datos  ', categories: %w[SURVEY SURVEY], definition: { screens: [{ title: 'T' }] })

      expect(flow.name).to eq('Datos')
      expect(flow.categories).to eq(['SURVEY'])
      expect(flow.reload.definition).to eq('screens' => [{ 'title' => 'T' }], 'schema_version' => 1)
    end
  end

  describe 'the definition' do
    it 'is checked and exported with the shared classes' do
      flow = build(:whatsapp_flow)

      expect(flow.definition_check).to be_valid
      expect(flow.flow_json).to include('version' => '7.3')
    end

    it 'reports the mistakes of a draft that is not ready' do
      flow = build(:whatsapp_flow, definition: { 'screens' => [{ 'title' => '', 'button' => '', 'blocks' => [] }] })

      expect(flow.definition_check.errors.pluck(:code)).to include('screen_title_required', 'button_required', 'blocks_required')
    end
  end
end
