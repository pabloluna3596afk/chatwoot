require 'rails_helper'

RSpec.describe Variables::Resolver do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, name: 'AGENTE interno', display_name: 'Nombre público', email: 'agent@example.com') }
  let(:contact) do
    create(:contact, account: account, name: 'MARÍA del CARMEN', document_number: 'DOC-123', country_code: 'EC',
                     additional_attributes: { 'country' => 'EC', 'country_code' => 'US' })
  end
  let(:conversation) { create(:conversation, account: account, contact: contact, assignee: agent) }
  let(:message) { build(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: agent, message_type: :outgoing) }
  let(:drops) { Variables::ContextFactory.new(account: account, records: { conversation: conversation, agent: agent }).build(surface: 'message') }
  let(:resolver) { described_class.new(drops: drops) }

  it 'reproduces MV-01: previews the column-only document and the documento binding exactly as sent' do
    expression = Variables::Catalog.new(account: account, surface: 'message').as_json[:variables]
                                   .find { |entry| entry[:aliases].include?('documento') }[:expression]
    message.content = expression
    message.save!

    expect(contact.additional_attributes).not_to have_key('document_number')
    expect(resolver.preview(expression)).to include(status: 'value', value: 'DOC-123')
    expect(message.content).to eq(resolver.preview(expression)[:value])
  end

  it 'reproduces MV-02: preserves Drop capitalization, last word surname and internal agent name' do
    text = '{{ contact.name }} / {{ contact.first_name }} / {{ contact.last_name }} / {{ agent.name }} / {{ agent.available_name }}'
    message.content = text
    message.save!

    expect(resolver.preview(text)[:value]).to eq('María Del Carmen / María / Carmen / Agente Interno / Nombre público')
    expect(message.content).to eq(resolver.preview(text)[:value])
  end

  it 'reproduces MV-03: uses the country column rather than conflicting additional attributes' do
    message.content = '{{ contact.country_code }}'
    message.save!

    expect(resolver.preview('{{ contact.country_code }}')).to include(status: 'value', value: 'EC')
    expect(message.content).to eq('EC')
  end

  it 'reads literal Unicode and punctuation keys without colliding with nested keys' do
    contact.update!(custom_attributes: { 'MARÍA' => 'sí', 'nivel.vip' => 'literal', 'nivel-vip' => 0, 'flag' => false,
                                         'nivel' => { 'vip' => 'nested' } })

    expect(resolver.preview("{{ contact.custom_attribute['MARÍA'] }}")[:value]).to eq('sí')
    expect(resolver.preview("{{ contact.custom_attribute['nivel.vip'] }}")[:value]).to eq('literal')
    expect(resolver.preview("{{ contact.custom_attribute['nivel-vip'] }}")).to include(status: 'value', value: '0')
    expect(resolver.preview('{{ contact.custom_attribute.flag }}')).to include(status: 'value', value: 'false')
  end

  it 'retains free Liquid, code protection and single rendering of values containing Liquid' do
    contact.update!(custom_attributes: { 'text' => '{{ contact.email }}' })
    text = 'Hi {{ contact.first_name | upcase }} `{{ contact.name }}` {{ contact.custom_attribute.text }}'
    message.content = text
    message.save!

    expect(resolver.preview(text, protect_code: true)[:value]).to eq('Hi MARÍA `{{ contact.name }}` {{ contact.email }}')
    expect(message.content).to eq(resolver.preview(text, protect_code: true)[:value])
  end

  it 'distinguishes missing values, absent contexts and invalid syntax or filters' do
    expect(resolver.preview('{{ contact.custom_attribute.absent }}')[:status]).to eq('missing')
    expect(resolver.preview('{{ appointment.title }}')[:status]).to eq('unavailable')
    expect(resolver.preview('{% if %}')[:status]).to eq('invalid')
    expect(resolver.preview('{{ contact.name | not_a_filter }}')[:status]).to eq('invalid')
    expect(resolver.preview('{{ contact.email | default: "fallback" }}')[:value]).to be_present
  end

  it 'reports a missing surname for a contact whose name is not set' do
    contact.update!(name: nil)

    expect(resolver.preview('{{ contact.last_name }}')).to include(status: 'missing', value: '')
  end

  it 'matches the current campaign sender and contact resolution without adding conversation' do
    campaign = create(:campaign, account: account, sender: agent)
    context = Variables::ContextFactory.new(account: account, records: { contact: contact, campaign: campaign }).build(surface: 'campaign')
    preview = described_class.new(drops: context)
    text = '{{ contact.document_number }} {{ contact.name }} {{ contact.country_code }} {{ agent.name }}'

    expect(preview.preview(text)[:value]).to eq(Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(text))
    expect(preview.preview('{{ conversation.id }}')[:status]).to eq('unavailable')
    expect(preview.preview('{{ date.today }}')[:status]).to eq('value')
  end

  it 'uses the account timezone on both sides of midnight without changing the process timezone' do
    account.update!(reporting_timezone: 'America/Guayaquil')
    travel_to Time.utc(2026, 10, 20, 2) do
      message.content = '{{ date.today }}'
      message.save!

      expect(resolver.preview('{{ date.today }}')).to include(status: 'value', value: '2026-10-19')
      expect(message.content).to eq('2026-10-19')
      expect(Variables::ContextFactory.timezone(account)).to eq('America/Guayaquil')
      expect(DateDrop.new.today).to eq(Time.current.to_date)
    end
  end
end
