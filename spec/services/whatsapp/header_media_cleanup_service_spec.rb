require 'rails_helper'

describe Whatsapp::HeaderMediaCleanupService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def header_blob(created_at: 40.days.ago, last_used_at: nil, name: 'oferta.pdf')
    metadata = { 'account_id' => account.id, Whatsapp::TemplateHeaderMedia::METADATA_KEY => true }
    metadata[Whatsapp::TemplateHeaderMedia::LAST_USED_KEY] = last_used_at.iso8601 if last_used_at
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 #{name} #{SecureRandom.hex(4)}"), filename: name, content_type: 'application/pdf', metadata: metadata
    ).tap { |blob| blob.update_columns(created_at: created_at) } # rubocop:disable Rails/SkipsModelValidations
  end

  def names_left
    ActiveStorage::Blob.pluck(:filename).map(&:to_s)
  end

  it 'purges a copy that nothing uses and was last chosen more than 30 days ago' do
    header_blob

    expect(described_class.new.perform).to eq(1)
    expect(names_left).to be_empty
  end

  it 'keeps a copy that is new, or was chosen again recently' do
    header_blob(created_at: 2.days.ago, name: 'nuevo.pdf')
    header_blob(last_used_at: 3.days.ago, name: 'reusado.pdf')

    expect(described_class.new.perform).to eq(0)
    expect(names_left).to contain_exactly('nuevo.pdf', 'reusado.pdf')
  end

  it 'keeps the file of a sent message: it is an attachment of that message' do
    blob = header_blob(name: 'enviado.pdf')
    message = create(:message, account: account, inbox: inbox, conversation: create(:conversation, account: account, inbox: inbox))
    attachment = message.attachments.build(account_id: account.id, file_type: :file)
    attachment.file.attach(blob)
    attachment.save!

    expect(described_class.new.perform).to eq(0)
    expect(names_left).to include('enviado.pdf')
  end

  def header_params(blob)
    { 'processed_params' => { 'header' => { 'media_blob' => blob.signed_id } } }
  end

  it 'keeps the file of a campaign, an automation rule and a Captain setting, and purges the rest' do
    campaign_blob = header_blob(name: 'campana.pdf')
    rule_blob = header_blob(name: 'regla.pdf')
    assistant_blob = header_blob(name: 'captain.pdf')
    header_blob(name: 'libre.pdf')
    campaign = create(:campaign, :whatsapp, account: account)
    campaign.update_columns(template_params: header_params(campaign_blob)) # rubocop:disable Rails/SkipsModelValidations
    create(:automation_rule, account: account,
                             actions: [{ 'action_name' => 'send_message', 'action_params' => [header_params(rule_blob)] }])
    create(:captain_assistant, account: account, config: { 'reengagement_template' => header_params(assistant_blob) })

    expect(described_class.new.perform).to eq(1)
    expect(names_left).to contain_exactly('campana.pdf', 'regla.pdf', 'captain.pdf')
  end

  it 'ignores files that are not template headers' do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'avatar.png', content_type: 'image/png')
                       .update_columns(created_at: 90.days.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.new.perform).to eq(0)
    expect(names_left).to eq(['avatar.png'])
  end
end
