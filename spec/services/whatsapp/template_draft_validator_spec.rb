require 'rails_helper'

RSpec.describe Whatsapp::TemplateDraftValidator do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:draft) do
    create(:whatsapp_template_draft, account: account, preferred_channel: channel, waba_id: channel.provider_config['business_account_id'])
  end

  it 'validates the complete payload locally using the existing builder' do
    payload = described_class.new(draft).snapshot!.fetch('payload')
    expect(payload).to include('name' => draft.name, 'parameter_format' => 'POSITIONAL', 'components' => [
                                 { 'type' => 'BODY', 'text' => draft.definition.dig('body', 'text') }
                               ])
  end

  it 'uses the same supported-language catalog as the existing template editor' do
    source = Rails.root.join('app/javascript/dashboard/routes/dashboard/settings/templates/whatsappLanguages.js').read
    catalog = source.match(/META_LANGUAGES = \[(.*?)\]/m)[1].scan(/'([^']+)'/).flatten
    expect(described_class::LANGUAGES).to match_array(catalog)
  end

  it 'rejects interleaved quick reply buttons locally' do
    draft.definition['buttons'] = [
      { 'type' => 'QUICK_REPLY', 'text' => 'Primero' },
      { 'type' => 'URL', 'text' => 'Abrir', 'url' => 'https://example.com' },
      { 'type' => 'QUICK_REPLY', 'text' => 'Último' }
    ]
    expect { described_class.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid) do |error|
      expect(error.code).to eq('invalid_button_grouping')
    end
  end

  [{ name: 'INVALID' }, { language: 'xx_XX' }, { category: 'AUTHENTICATION' }, { waba_id: nil, preferred_channel: nil },
   { definition: {} }, { definition: { 'body' => { 'text' => 'Hola {{name}}.' } } },
   { definition: { 'header' => { 'format' => 'IMAGE' }, 'body' => { 'text' => 'Hola.' } } },
   { definition: { 'body' => { 'text' => 'Hola {{first1}}, gracias.', 'examples' => ['Ana'] } } },
   { archived_at: Time.current }].each do |attributes|
    it "rejects incomplete or invalid submission content #{attributes.keys.join(', ')} without HTTP" do
      draft.assign_attributes(attributes)
      expect { described_class.new(draft).snapshot! }.to raise_error(Whatsapp::TemplateComponentsBuilder::Invalid)
    end
  end
end
