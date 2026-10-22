require 'rails_helper'
require Rails.root.join('db/migrate/20261022130000_add_audience_to_captain_inboxes')

RSpec.describe AddAudienceToCaptainInboxes, type: :model do
  let(:migration) { described_class.new }
  let(:database) { ActiveRecord::Base.connection }

  before do
    database.create_table(:captain_audience_migration_check, temporary: true) { |table| table.string :marker }
    database.execute("INSERT INTO captain_audience_migration_check (marker) VALUES ('existing')")
    [:add_column, :remove_column].each do |method|
      allow(database).to receive(method).and_wrap_original do |original, _table, *arguments, **options|
        original.call(:captain_audience_migration_check, *arguments, **options)
      end
    end
  end

  after { database.drop_table(:captain_audience_migration_check, if_exists: true) }

  it 'adds non-null defaults without rewriting existing connection settings' do
    migration.migrate(:up)

    row = database.select_one('SELECT marker, audience_mode, audience_rules FROM captain_audience_migration_check')
    columns = database.columns(:captain_audience_migration_check).index_by(&:name)

    expect(row).to include('marker' => 'existing', 'audience_mode' => 'inherit', 'audience_rules' => '{}')
    expect(columns.fetch('audience_mode').null).to be(false)
    expect(columns.fetch('audience_rules').null).to be(false)
    expect(columns.fetch('audience_mode').default).to eq('inherit')
    expect(columns.fetch('audience_rules').default).to eq('{}')
  end

  it 'is reversible on the same connection and transaction' do
    migration.migrate(:up)
    migration.migrate(:down)

    expect(database.columns(:captain_audience_migration_check).map(&:name)).to eq(%w[id marker])
    expect(database.select_value('SELECT marker FROM captain_audience_migration_check')).to eq('existing')
  end
end
