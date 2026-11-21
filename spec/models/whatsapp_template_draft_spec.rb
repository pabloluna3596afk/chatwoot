require 'rails_helper'

RSpec.describe WhatsappTemplateDraft do
  let(:account) { create(:account) }
  let(:draft) { build(:whatsapp_template_draft, account: account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  it 'stores incomplete content without HTTP or a destination' do
    draft.assign_attributes(name: nil, language: nil, category: nil, definition: {})
    expect { draft.save! }.not_to raise_error
    expect(draft.reload.definition).to eq({})
    expect(draft.submissions).to be_empty
  end

  it 'rejects malformed definition fields without coercing values' do
    [[], { 'body' => [] }, { 'body' => { 'text' => 1 } }, { 'buttons' => {} },
     { 'header' => { 'examples' => [nil] } }, { 'header' => { 'handle' => 'remote' } },
     { 'preserved' => { 'buttons' => [{ 'position' => -1, 'button' => {} }] } }].each do |definition|
      draft.definition = definition
      expect(draft).not_to be_valid
      expect(draft.errors[:definition]).to be_present
    end
  end

  it 'bounds stored content and rejects non-string scalar values' do
    draft.definition = { 'body' => { 'text' => 'a' * (described_class::MAX_DEFINITION_BYTES + 1) } }
    draft.name = 123
    draft.variable_bindings = { 'name' => [] }
    expect(draft).not_to be_valid
    expect(draft.errors.attribute_names).to include(:definition, :name, :variable_bindings)
  end

  it 'checks destination and authors within the account' do
    draft.preferred_channel = channel
    draft.waba_id = 'another_waba'
    draft.created_by = create(:user)
    expect(draft).not_to be_valid
    expect(draft.errors.attribute_names).to include(:preferred_channel, :waba_id, :created_by)
  end

  it 'reserves a complete identity per account and WABA, including the database constraint' do
    draft.assign_attributes(preferred_channel: channel, waba_id: channel.provider_config['business_account_id'])
    draft.save!
    other = draft.dup
    expect(other).not_to be_valid
    expect { other.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'does not reserve an incomplete identity and releases archived draft identities' do
    draft.save!
    expect(draft.dup).to be_valid
    draft.update!(waba_id: channel.provider_config['business_account_id'], archived_at: Time.current)
    expect(draft.dup.tap { |copy| copy.archived_at = nil }).to be_valid
  end

  it 'rejects stale concurrent edits' do
    draft.save!
    stale = described_class.find(draft.id)
    draft.update!(title: 'Primero')
    expect { stale.update!(title: 'Segundo') }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it 'stores a local attachment and rejects unsupported files' do
    draft.media.attach(io: StringIO.new('image bytes'), filename: 'example.png', content_type: 'image/png')
    draft.save!
    expect(draft.reload.media.download).to eq('image bytes')
    draft.media.attach(io: StringIO.new('executable'), filename: 'example.exe', content_type: 'application/octet-stream')
    expect(draft).not_to be_valid
  end
end
