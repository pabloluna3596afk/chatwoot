require 'rails_helper'

RSpec.describe Captain::AppointmentFormat do
  let(:zone) { Time.find_zone!('America/Guayaquil') }
  let(:thursday) { Time.find_zone!('UTC').parse('2030-10-03T16:30:00Z') } # 11:30 in Guayaquil, a Thursday
  let(:wednesday_evening) { Time.find_zone!('UTC').parse('2030-09-04T03:05:00Z') } # Sep 3rd, 22:05 in Guayaquil

  it 'writes the long date in Spanish without zero padding, in the timezone of the account' do
    expect(described_class.long(thursday, locale: 'es', zone: zone)).to eq('jueves 3 de octubre, 11:30')
    expect(described_class.long(wednesday_evening, locale: 'es', zone: zone)).to eq('martes 3 de septiembre, 22:05')
  end

  it 'writes the short date for the buttons' do
    expect(described_class.short(thursday, locale: 'es', zone: zone)).to eq('jue 3 oct · 11:30')
  end

  it 'writes both in English' do
    expect(described_class.long(thursday, locale: 'en', zone: zone)).to eq('Thursday, October 3, 11:30')
    expect(described_class.short(thursday, locale: 'en', zone: zone)).to eq('Thu, Oct 3 · 11:30')
  end

  it 'writes the day alone and the clock alone' do
    expect(described_class.day(thursday, locale: 'es', zone: zone)).to eq('jueves 3 de octubre')
    expect(described_class.clock(thursday, zone: zone)).to eq('11:30')
  end

  it 'keeps every short date within the 20 characters of a WhatsApp button title' do
    zone_utc = Time.find_zone!('UTC')
    longest = (1..12).flat_map do |month|
      (1..28).flat_map do |day|
        %w[es en].map { |locale| described_class.short(zone_utc.local(2030, month, day, 23, 59), locale: locale, zone: zone_utc).length }
      end
    end.max

    expect(longest).to be <= 20
  end
end
