class Captain::Decisions::Sources
  def self.build(account:, assistant_id:, evidence:)
    assistant = account.captain_assistants.find_by(id: assistant_id)
    return {} unless assistant

    faqs = assistant.responses.approved.where(id: evidence['used_faq_ids'], documentable_type: 'User').map do |faq|
      { id: faq.id, title: faq.question, usage: 'used' }
    end
    { documents: documents(assistant, evidence), faqs: faqs }
  end

  def self.documents(assistant, evidence)
    document_ids = Array(evidence['document_ids']) | Array(evidence['cited_document_ids'])
    assistant.documents.where(id: document_ids).map do |document|
      { id: document.id, title: document.name, link: safe_link(document.display_url),
        usage: Array(evidence['cited_document_ids']).include?(document.id) ? 'cited' : 'consulted' }
    end
  end

  def self.safe_link(link)
    uri = URI.parse(link.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host && !uri.userinfo && !uri.query && !uri.fragment

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
