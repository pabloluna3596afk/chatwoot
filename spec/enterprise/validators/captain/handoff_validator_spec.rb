require 'rails_helper'

RSpec.describe Captain::HandoffValidator do
  let(:assistant) { create(:captain_assistant) }

  [nil, false, [], 'inbox', { 'unknown' => {} }, { 'new' => nil }, { 'new' => { 'mode' => 'unassigned' } },
   { 'new' => { 'mode' => 'inbox', 'extra' => true } }, { 'new' => { 'mode' => 'team' } },
   { 'new' => { 'mode' => 'inbox', 'team_id' => 1 } }].each do |value|
    it "rejects invalid routing #{value.inspect}" do
      assistant.config['handoff_routing'] = value
      expect(assistant).not_to be_valid
    end
  end

  it 'rejects a team from another account and string IDs' do
    team = create(:team)
    assistant.config['handoff_routing'] = { 'new' => { 'mode' => 'team', 'team_id' => team.id } }
    expect(assistant).not_to be_valid
    assistant.config['handoff_routing']['new']['team_id'] = team.id.to_s
    expect(assistant).not_to be_valid
  end

  it 'allows a team without members and fills missing defaults on read' do
    team = create(:team, account: assistant.account)
    assistant.config['handoff_routing'] = { 'new' => { 'mode' => 'team', 'team_id' => team.id } }
    expect(assistant).to be_valid
    expect(assistant.handoff_routing['reopened']).to eq('mode' => 'inbox', 'team_id' => nil)
    expect(assistant.handoff_priority).to eq('off')
  end

  [nil, false, [], 'high'].each do |value|
    it "rejects invalid priority #{value.inspect}" do
      assistant.config['handoff_priority'] = value
      expect(assistant).not_to be_valid
    end
  end
end
