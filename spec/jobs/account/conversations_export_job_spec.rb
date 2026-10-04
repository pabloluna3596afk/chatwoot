require 'rails_helper'

RSpec.describe Account::ConversationsExportJob do
  let(:account) { create(:account) }
  let(:job) { described_class.new.tap { |instance| instance.instance_variable_set(:@account, account) } }
  let(:headers) { %w[display_id contact_name contact_phone] }
  let(:rows) { [[7, '=HYPERLINK(http://evil.example)', '+593999999999']] }

  describe 'formula characters in exported values' do
    it 'escapes them in the CSV' do
      job.send(:attach_csv, headers, rows)

      csv_content = account.conversations_export.download.force_encoding('UTF-8').delete_prefix("\xEF\xBB\xBF")
      row = CSV.parse(csv_content, headers: true).first

      expect(row['contact_name']).to eq("'=HYPERLINK(http://evil.example)")
      expect(row['contact_phone']).to eq("'+593999999999")
      expect(row['display_id']).to eq("\t7")
    end

    it 'never stores them as a formula in the XLSX' do
      job.send(:attach_xlsx, headers, rows)

      xml = xlsx_xml(account.conversations_export.download)

      expect(xml[:sheets]).not_to include('<f>')
      expect(xml[:all]).to include('HYPERLINK')
    end
  end
end
