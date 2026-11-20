require 'rails_helper'

RSpec.describe 'dev:captain_decisions_demo' do # rubocop:disable RSpec/DescribeClass -- named Rake entry point
  let(:task) { Rake::Task['dev:captain_decisions_demo'] }
  let(:account) { create(:account) }

  it 'creates isolated, idempotent fictional decisions without enqueuing delivery or AI jobs', :aggregate_failures do
    create(:user, account: account, role: :administrator)
    clear_enqueued_jobs
    with_modified_env ACCOUNT_ID: account.id.to_s do
      expect { task.execute }.to output(/Fictional demo:.*conversations/).to_stdout
      conversation = account.conversations.sole
      expect(conversation.messages.count).to eq(6)
      expect(account.captain_decisions.count).to eq(6)
      expect(conversation.messages.where(private: true).sole.content_attributes).to have_key('captain_handoff')
      expect(conversation.messages.activity.count).to eq(3)
      expect(account.captain_decisions.where("technical_details ->> 'credits_consumed' = '0'").count).to eq(3)
      expect(account.captain_decisions.where(technical_details: {}).count).to eq(2)
      expect { task.execute }.to output(/Fictional demo/).to_stdout
      expect(account.conversations.count).to eq(1)
      expect(conversation.messages.count).to eq(6)
      expect(account.captain_decisions.count).to eq(6)
      expect(enqueued_jobs).to be_empty
    end
  end

  it 'aborts in production before reading an account' do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect(Account).not_to receive(:find)
    expect { task.execute }.to raise_error(SystemExit, /disabled in production/).and output(/disabled in production/).to_stderr
  end
end
