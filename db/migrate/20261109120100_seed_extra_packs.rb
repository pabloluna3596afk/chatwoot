class SeedExtraPacks < ActiveRecord::Migration[7.0]
  PACKS = YAML.safe_load_file(Rails.root.join('db/seeds/extra_packs.yml')).freeze

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
