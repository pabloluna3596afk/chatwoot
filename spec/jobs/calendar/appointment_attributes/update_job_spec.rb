require 'rails_helper'

RSpec.describe Calendar::AppointmentAttributes::UpdateJob do
  let(:contact) { create(:contact) }
  let(:account) { contact.account }

  before { Calendar::AppointmentAttributes::Provisioner.new(account: account).perform(keys: ['total_citas']) }

  it 'recalculates an existing contact' do
    described_class.perform_now(account.id, contact.id)

    expect(contact.reload.custom_attributes['total_citas']).to eq(0)
  end

  it 'ignores a deleted contact' do
    expect { described_class.perform_now(account.id, -1) }.not_to raise_error
  end

  it 'does not update contacts from another account' do
    other = create(:account)

    expect { described_class.perform_now(other.id, contact.id) }.not_to(change { contact.reload.custom_attributes })
  end
end
