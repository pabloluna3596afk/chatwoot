require 'rails_helper'

RSpec.describe Variables::DeliveryRenderer do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, email: nil, custom_attributes: { 'zero' => 0, 'flag' => false }) }
  let(:drops) { Variables::ContextFactory.new(account: account, records: { contact: contact }).build(surface: 'campaign') }
  let(:renderer) { described_class.new(drops: drops) }

  it 'rejects a missing value inside nonempty text' do
    expect { renderer.render('Hello {{ contact.email }}!') }.to raise_error(described_class::Error, 'content: missing')
  end

  it 'reports the nested parameter and unavailable context without sending partial content' do
    expect { renderer.render({ 'buttons' => [{ 'text' => '{{ appointment.title }}' }] }) }
      .to raise_error(described_class::Error, 'content.buttons[0].text: unavailable')
  end

  it 'rejects invalid references and filters' do
    expect { renderer.render('{{ unknown.reference }}') }.to raise_error(described_class::Error, 'content: missing')
    expect { renderer.render('{{ contact.name | unknown_filter }}') }.to raise_error(described_class::Error, 'content: invalid')
    expect { renderer.render('{{ contact.name') }.to raise_error(described_class::Error, 'content: invalid')
  end

  it 'keeps filters, zero, false, code protection and data containing Liquid' do
    contact.update!(custom_attributes: contact.custom_attributes.merge('text' => '{{ contact.email }}'))
    text = '{{ contact.email | default: "fallback" }} {{ contact.custom_attribute.zero }} {{ contact.custom_attribute.flag }}'
    expect(renderer.render(text)).to eq('fallback 0 false')
    expect(renderer.render('{{ contact.custom_attribute.text }}')).to eq('{{ contact.email }}')
    expect(renderer.render('`{{ contact.email }}`', protect_code: true)).to eq('`{{ contact.email }}`')
  end

  it 'does not evaluate outputs from an inactive Liquid branch' do
    expect(renderer.render('{% if false %}{{ contact.email }}{% else %}OK{% endif %}')).to eq('OK')
  end

  it 'keeps legacy hash/array shapes and JSON-sensitive data unchanged' do
    contact.update!(custom_attributes: { 'text' => "a\"b\nc\\d" })
    expect(renderer.render({ '1' => '{{ contact.custom_attribute.text }}', 'body' => ['static', nil, 0] }))
      .to eq({ '1' => "a\"b\nc\\d", 'body' => ['static', nil, 0] })
  end
end
