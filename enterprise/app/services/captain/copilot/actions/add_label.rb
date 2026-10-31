class Captain::Copilot::Actions::AddLabel < Captain::Copilot::Actions::Base
  def self.action_name = 'add_label'

  def self.schema
    { type: 'object', description: 'Add an existing account label. Use list_labels to find label_id.',
      examples: [{ label_id: 12 }], required: %w[label_id], additionalProperties: false,
      properties: { label_id: { type: 'integer' } } }
  end

  def validate_payload!
    validate_payload_keys!(%w[label_id], 'Use list_labels to find the integer label_id.')
    raise ArgumentError, 'payload must be { label_id: integer }; use list_labels to get the id' unless @payload['label_id'].is_a?(Integer)

    label = @account.labels.find_by(id: @payload['label_id'])
    raise ArgumentError, 'label_id was not found in this account; use list_labels to get a valid id' if label.blank?

    @label = label
  end

  def preview = super.merge(label: { id: @label.id, name: @label.title })

  def execute
    target.label_list.add(@label.title)
    target.save!
    { code: 'label_added', label: @label.title }
  end
end
