require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::ListLabelsService do
  let(:account) { create(:account) }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'lists labels from the current account only' do
    label = create(:label, account: account, title: 'billing')
    create(:label, account: create(:account), title: 'private')

    expect(described_class.new(assistant, user: user).execute).to include(id: label.id, name: 'billing')
    expect(described_class.new(assistant, user: user).execute.map { |row| row[:name] }).not_to include('private')
  end
end
