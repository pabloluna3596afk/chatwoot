# The same authorized, actually selected citations feed the decision and the optional session capture.
class Captain::Assistant::CitationDocumentIds
  def self.call(assistant:, message:, context:)
    return [] unless assistant.config['feature_citation']

    document_ids = (context.dig(:state, Captain::Assistant::CITATION_SOURCES_STATE_KEY) || {}).transform_keys(&:to_i)
    visible_indexes = assistant.customer_visible_citation_urls(document_ids).keys
    stored_parts = message.additional_attributes.to_h[Captain::Assistant::ResponseParts::MESSAGE_ATTRIBUTE_KEY]
    selected_indexes = Captain::Assistant::ResponseParts.new(stored_parts).to_a.flat_map { |part| part['citation_indexes'] }.uniq
    (selected_indexes & visible_indexes).filter_map { |index| document_ids[index] }.uniq
  end
end
