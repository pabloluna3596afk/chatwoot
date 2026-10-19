require 'rails_helper'

RSpec.describe Plan do
  subject(:plan) { described_class.new(name: 'Inicio', slug: 'inicio') }

  it 'defaults to no daily free tests' do
    expect(plan.captain_daily_tests).to eq(0)
  end

  it 'accepts a nonnegative integer allowance' do
    plan.captain_daily_tests = 35
    expect(plan).to be_valid
  end

  it 'rejects negative, fractional and missing allowances' do
    [-1, 1.5, nil].each do |value|
      plan.captain_daily_tests = value
      expect(plan).not_to be_valid
      expect(plan.errors[:captain_daily_tests]).to be_present
    end
  end
end
