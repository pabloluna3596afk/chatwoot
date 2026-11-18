require 'rails_helper'

RSpec.describe Captain::TemplateDailyCap do
  let(:account) { create(:account) }

  it 'defaults to 50 template sends per account day' do
    cap = described_class.new(account)

    50.times { expect(cap.reserve!).to be(true) }
    expect(cap.reserve!).to be(false)
    expect(cap.used).to eq(50)
  end

  it 'treats a configured zero as no template sends and releases failed sends' do
    account.update!(captain_template_daily_cap: 0)
    cap = described_class.new(account)

    expect(cap.reserve!).to be(false)
    account.update!(captain_template_daily_cap: 1)
    expect(cap.reserve!).to be(true)
    cap.release!
    expect(cap.used).to eq(0)
  end
end
