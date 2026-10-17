require 'rails_helper'

RSpec.describe Onboarding::InboxMemberAssignmentService do
  let(:account) { create(:account, custom_attributes: { onboarding_version: 2, onboarding_step: 'inbox_setup' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:account_user) { account.account_users.find_by!(user: admin) }
  let(:inbox) { create(:inbox, account: account) }
  let(:service) { described_class.new(account, account_user) }

  it 'assigns only the current administrator to every empty inbox in the account' do
    another_inbox = create(:inbox, account: account)
    other_account_inbox = create(:inbox)
    create(:user, account: account, role: :agent)
    inbox

    service.perform

    expect(inbox.members).to contain_exactly(admin)
    expect(another_inbox.members).to contain_exactly(admin)
    expect(other_account_inbox.members).to be_empty
  end

  it 'does not duplicate the membership on a second call' do
    inbox
    service.perform

    expect { service.perform }.not_to change(InboxMember, :count)
    expect(inbox.members).to contain_exactly(admin)
  end

  it 'preserves existing members without adding the administrator' do
    agent = create(:user, account: account, role: :agent)
    inbox.add_members([agent.id])

    expect { service.perform }.not_to change(InboxMember, :count)
    expect(inbox.members).to contain_exactly(agent)
  end

  it 'does not change accounts without an onboarding version' do
    inbox
    account.update!(custom_attributes: { onboarding_step: 'inbox_setup' })

    expect { service.perform }.not_to change(InboxMember, :count)
  end

  it 'does not change accounts outside inbox_setup' do
    inbox
    account.update!(custom_attributes: { onboarding_version: 2 })

    expect { service.perform }.not_to change(InboxMember, :count)
  end

  it 'does not assign an agent making an embedded signup request' do
    inbox
    account_user.update!(role: :agent)

    expect { service.perform }.not_to change(InboxMember, :count)
  end

  it 'does not assign a bot making an embedded signup request' do
    inbox

    expect { described_class.new(account, nil).perform }.not_to change(InboxMember, :count)
  end
end
