class SeedExtraPacks < ActiveRecord::Migration[7.0]
  PACKS = {
    captain_responses: [[500, 20], [2000, 64], [5000, 140]],
    internal: [[500, 6], [2000, 20], [5000, 45]],
    copilot: [[1000, 5], [5000, 20]]
  }.freeze

  def up
    packs = Class.new(ActiveRecord::Base) { self.table_name = 'extra_packs' }
    PACKS.each do |bucket, prices|
      prices.each_with_index do |(units, price), order|
        packs.create!(bucket: bucket, units: units, price_usd: price, display_order: order)
      end
    end
  end

  def down
    execute 'DELETE FROM extra_packs'
  end
end
