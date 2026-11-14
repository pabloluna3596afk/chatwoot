# Examples that turn off transactional tests commit their records, and associations destroyed asynchronously or
# without an account_id (captain_inboxes, contact_inboxes, audits) outlive them. Use this context to leave the
# database empty again, so later examples that count records do not see them.
RSpec.shared_context 'with an empty database after the example' do
  after do
    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    connection.execute("TRUNCATE TABLE #{tables.map { |table| connection.quote_table_name(table) }.join(', ')} RESTART IDENTITY CASCADE")
  end
end
