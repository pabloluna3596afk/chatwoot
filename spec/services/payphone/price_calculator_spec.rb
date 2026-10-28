require 'rails_helper'

RSpec.describe Payphone::PriceCalculator do
  describe '.call' do
    it 'calculates every invoice and commission combination for the plan catalog' do
      examples = {
        19 => { untaxed_with_commission: 2009, untaxed: 1900, invoiced: 2185, invoiced_with_commission: 2311 },
        79 => { untaxed_with_commission: 8354, untaxed: 7900, invoiced: 9085, invoiced_with_commission: 9607 },
        119 => { untaxed_with_commission: 12_584, untaxed: 11_900, invoiced: 13_685, invoiced_with_commission: 14_472 },
        299 => { untaxed_with_commission: 31_619, untaxed: 29_900, invoiced: 34_385, invoiced_with_commission: 36_362 },
        599 => { untaxed_with_commission: 63_344, untaxed: 59_900, invoiced: 68_885, invoiced_with_commission: 72_846 }
      }

      examples.each do |price, totals|
        scenarios = [
          [false, true, totals[:untaxed_with_commission]],
          [false, false, totals[:untaxed]],
          [true, false, totals[:invoiced]],
          [true, true, totals[:invoiced_with_commission]]
        ]

        scenarios.each do |needs_invoice, commission_enabled, expected_total|
          result = described_class.call(
            price: price,
            needs_invoice: needs_invoice,
            commission_enabled: commission_enabled
          )

          expect(result.total_cents).to eq(expected_total)
          expect(result.total_cents).to eq(
            result.amount_without_tax + result.amount_with_tax + result.tax + result.service
          )
          expect(result.base_cents).to eq(price * 100)
        end
      end
    end

    it 'rounds percentage components half up to the cent' do
      result = described_class.call(price: '0.10', needs_invoice: true, tax_rate: '15', commission_enabled: false)

      expect(result.base_cents).to eq(10)
      expect(result.tax_cents).to eq(2)
      expect(result.total_cents).to eq(12)
    end
  end
end
