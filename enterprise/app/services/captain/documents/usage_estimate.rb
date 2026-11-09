require 'pdf/reader'

class Captain::Documents::UsageEstimate
  def self.pdf_pages(file)
    unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.content_type == 'application/pdf'
      raise CustomExceptions::Pdf::EstimateError, I18n.t('captain.documents.pdf_format_error')
    end
    raise CustomExceptions::Pdf::EstimateError, I18n.t('captain.documents.pdf_size_error') if file.size > 10.megabytes

    pages = PDF::Reader.new(file.tempfile).page_count
    raise CustomExceptions::Pdf::EstimateError, I18n.t('captain.documents.invalid_pdf') unless pages.positive?

    pages
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    raise CustomExceptions::Pdf::EstimateError, I18n.t('captain.documents.invalid_pdf')
  end

  def self.for_upload(account:, pdf_file: nil)
    pages = pdf_pages(pdf_file) if pdf_file
    units = if pages
              capped_pages = [pages, Llm::UnitCosts.fetch(:pdf, :max_pages)].min
              (capped_pages.to_f / Llm::UnitCosts.fetch(:pdf, :pages_per_chunk)).ceil * Llm::UnitCosts.fetch(:pdf, :units_per_chunk)
            else
              Llm::UnitCosts.fetch(:text, :units_per_chunk)
            end
    for_units(account: account, units: units).merge(pages ? { pages: pages } : {})
  end

  def self.for_units(account:, units:)
    limits = account.usage_limits.fetch(:captain).fetch(:internal)
    remaining = limits[:current_available] if limits[:total_count]
    { units: units, remaining: remaining, sufficient: remaining.nil? || units <= remaining }
  end
end
