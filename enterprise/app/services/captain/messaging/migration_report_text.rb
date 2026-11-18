class Captain::Messaging::MigrationReportText
  REVIEW_STATES = %w[new marketing_off needs_review/unsupported authentication needs_data pending/rejected not_published_here].freeze

  def initialize(report)
    @report = report
  end

  def render
    Array(@report['inboxes']).map { |inbox| render_inbox(inbox) }.join("\n\n")
  end

  private

  def render_inbox(inbox)
    summary = inbox.fetch('summary')
    states = summary.fetch('after_auto_would_allow')
    differences = summary.fetch('differences')
    ["Bandeja: #{summary.fetch('inbox_name')} (##{inbox.fetch('inbox_id')})",
     "Hoy puede enviar: #{list(summary.fetch('before').values.flatten.map { |item| item.fetch('name') })}",
     "Con el modo automático podría enviar: #{list(states.fetch('available', []))}",
     "Ganaría: #{list(differences.fetch('gained'))}",
     "Perdería: #{list(differences.fetch('lost'))}",
     "Necesita revisión: #{list(REVIEW_STATES.flat_map { |state| states.fetch(state, []) }.uniq)}"].join("\n")
  end

  def list(names)
    names.present? ? names.join(', ') : '(ninguno)'
  end
end
