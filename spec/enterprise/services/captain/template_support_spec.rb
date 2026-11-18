require 'rails_helper'

RSpec.describe Captain::TemplateSupport do
  it 'allows text components and static buttons' do
    template = { 'components' => [
      { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order {{1}}' },
      { 'type' => 'BODY', 'text' => 'Ready' },
      { 'type' => 'FOOTER', 'text' => 'Thanks' },
      { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY' }, { 'type' => 'PHONE_NUMBER' }, { 'type' => 'URL', 'url' => 'https://example.com' }] }
    ] }

    expect(described_class.supported?(template)).to be(true)
    expect(described_class.url_button?(template)).to be(true)
  end

  it 'rejects media headers, dynamic URLs, and unknown components' do
    templates = [
      { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }] },
      { 'components' => [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{1}}' }] }] },
      { 'components' => [{ 'type' => 'CAROUSEL' }] }
    ]

    expect(templates.map { |template| described_class.supported?(template) }).to eq([false, false, false])
  end
end
