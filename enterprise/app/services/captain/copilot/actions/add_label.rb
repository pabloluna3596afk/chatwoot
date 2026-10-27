class Captain::Copilot::Actions::AddLabel < Captain::Copilot::Actions::Base
  def self.action_name = 'add_label'

  def self.schema
    { type: 'object', required: %w[label_id], additionalProperties: false,
      properties: { label_id: { type: 'integer' } } }
  end

  def validate_payload!
    validate_payload_keys!(%w[label_id])
    raise ArgumentError, 'label_id must be an integer' unless @payload['label_id'].is_a?(Integer)

    label = @account.labels.find_by(id: @payload['label_id'])
    raise ArgumentError, 'Label does not exist in this account' if label.blank?

    @label = label
  end

  def preview = super.merge(label: { id: @label.id, name: @label.title })

  def execute
    target.label_list.add(@label.title)
    target.save!
    { code: 'label_added', label: @label.title }
  end
end
