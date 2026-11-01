require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::ListAgentsService do
  let(:account) { create(:account) }
  let(:user) { create(:user, role: 'administrator', account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'lists only agents and teams belonging to the assistant account' do
    agent = create(:user, account: account, name: 'Ada Agent')
    team = create(:team, account: account, name: 'Support')
    create(:user, account: create(:account), name: 'Other Agent')
    create(:team, account: create(:account), name: 'Other Team')

    agents = described_class.new(assistant, user: user)
    teams = Captain::Tools::Copilot::ListTeamsService.new(assistant, user: user)

    expect(agents.execute).to include(id: agent.id, name: 'Ada Agent')
    expect(agents.execute.map { |row| row[:name] }).not_to include('Other Agent')
    expect(teams.execute).to include(id: team.id, name: team.name)
    expect(teams.execute.map { |row| row[:name] }).not_to include('Other Team')
  end

  it 'requires conversation management permission to expose assignment targets' do
    viewer = create(:user, role: 'agent', account: account)
    account_user = account.account_users.find_by!(user: viewer)
    account_user.update!(custom_role: create(:custom_role, account: account, permissions: ['contact_manage']))

    expect(described_class.new(assistant, user: viewer)).not_to be_active
    expect(Captain::Tools::Copilot::ListTeamsService.new(assistant, user: viewer)).not_to be_active
  end
end
