require 'rails_helper'

RSpec.describe Captain::TemplateDailyCap do
  let(:account) { create(:account, reporting_timezone: 'America/Guayaquil') }
  let(:now) do
    Time.use_zone(Integrations::GoogleCalendar::Timezone.for(account)) { Time.zone.parse('2030-01-15 23:59:30') }
  end

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

  it 'resets at midnight in the account time zone' do
    travel_to(now) do
      expect(described_class.new(account).reserve!).to be(true)
      expect(described_class.new(account).used).to eq(1)

      travel(1.minute)
      expect(described_class.new(account).used).to eq(0)
    end
  end

  it 'emails administrators once when the daily limit is first exceeded' do
    account.update!(captain_template_daily_cap: 0)
    mail = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    expect(mail).to receive(:deliver_later).once
    expect(AdministratorNotifications::AccountNotificationMailer).to receive(:captain_template_cap_reached)
      .once.with(account, 0).and_return(mail)

    travel_to(now) do
      cap = described_class.new(account)
      expect(cap.reserve!).to be(false)
      expect(cap.reserve!).to be(false)
    end
  end

  it 'allows only one reservation when callers race for the last daily slot' do
    account.update!(captain_template_daily_cap: 1)
    start = Queue.new
    ready = Queue.new
    results = Array.new(8) do
      Thread.new do
        ready << true
        start.pop
        described_class.new(account, now: now).reserve!
      end
    end
    results.size.times { ready.pop }
    results.size.times { start << true }

    expect(results.map(&:value).count(true)).to eq(1)
    expect(described_class.new(account, now: now).used).to eq(1)
  end

  it 'keeps the original counter and reset boundary after a timezone edit' do
    account.update!(captain_template_daily_cap: 1)
    travel_to(now) do
      expect(described_class.new(account).reserve!).to be(true)
      account.update!(reporting_timezone: 'Asia/Tokyo')
      expect(described_class.new(account.reload).used).to eq(1)
      expect(described_class.new(account).reserve!).to be(false)
      travel(1.minute)
      expect(described_class.new(account).used).to eq(0)
      expect(described_class.new(account).reserve!).to be(true)
    end
  end
end
