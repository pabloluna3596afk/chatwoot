require 'rails_helper'

RSpec.describe Captain::TemplateReference do
  let(:account) { create(:account) }
  let(:entry) do
    { 'name' => 'promo', 'language' => 'es', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Hola {{1}}' }] }
  end
  let(:file) do
    { 'media_id' => '555', 'media_blob' => 'signed', 'media_url' => 'https://example.com/promo.png', 'media_name' => 'promo.png',
      'media_type' => 'image', 'media_uploaded_at' => '2030-01-01T00:00:00Z', 'media_phone_number_id' => '123' }
  end

  before do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [entry])
  end

  describe '.errors' do
    it 'refuses a template whose header needs a file and has none' do
      reference = described_class.cast('name' => 'promo', 'language' => 'es', 'processed_params' => { 'body' => { '1' => 'Ana' } })

      expect(described_class.errors(reference, account)).to eq(['the header needs a file (image, video or document)'])
    end

    it 'accepts it once the file is there, and does not read its keys as Liquid' do
      reference = described_class.cast(
        'name' => 'promo', 'language' => 'es',
        'processed_params' => { 'body' => { '1' => 'Ana' }, 'header' => file.merge('media_name' => '{% bad') }
      )

      expect(described_class.errors(reference, account)).to be_empty
      expect(reference['processed_params']['header']).to include('media_id' => '555', 'media_blob' => 'signed')
    end
  end
end
