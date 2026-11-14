require 'rails_helper'

RSpec.describe Captain::BusinessFactsValidator do
  let(:assistant) { build(:captain_assistant, account: create(:account)) }

  it 'accepts the five known keys' do
    assistant.config['business_facts'] = described_class::FIELDS.index_with { 'x' * 300 }

    expect(assistant).to be_valid
  end

  it 'rejects an unknown key' do
    assistant.config['business_facts'] = { 'unknown' => 'text' }

    expect(assistant).not_to be_valid
    expect(assistant.errors[:config]).to be_present
  end

  it 'rejects more than 300 characters' do
    assistant.config['business_facts'] = { 'hours' => 'x' * 301 }

    expect(assistant).not_to be_valid
  end

  it 'accepts a missing hash' do
    expect(assistant).to be_valid
  end

  it 'accepts an empty hash and empty text' do
    assistant.config['business_facts'] = {}
    expect(assistant).to be_valid
    assistant.config['business_facts'] = { 'hours' => '' }
    expect(assistant).to be_valid
  end

  [false, [], 'text', { 'hours' => nil }, { 'hours' => 12 }, { 'hours' => ['Monday'] }].each do |invalid|
    it "rejects invalid types #{invalid.inspect}" do
      assistant.config['business_facts'] = invalid

      expect(assistant).not_to be_valid
      expect(assistant.errors[:config]).to be_present
    end
  end
end
