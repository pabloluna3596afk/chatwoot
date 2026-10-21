class Captain::VariableDiagnostics
  KEY = 'variable_delivery_error'.freeze

  def self.record(assistant, error, template:)
    diagnostic = { template: template['name'], language: template['language'], path: error.path,
                   status: error.status, at: Time.current.utc.iso8601 }
    expression = ApplicationRecord.sanitize_sql_array(["jsonb_set(config, '{#{KEY}}', ?::jsonb)", diagnostic.to_json])
    assistant.class.where(id: assistant.id).update_all(config: Arel.sql(expression)) # rubocop:disable Rails/SkipsModelValidations
  end
end
