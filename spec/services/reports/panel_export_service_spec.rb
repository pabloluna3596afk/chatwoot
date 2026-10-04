require 'rails_helper'

RSpec.describe Reports::PanelExportService do
  it 'never stores a panel name or a cell as a formula in the XLSX' do
    result = {
      name: '=HYPERLINK(http://evil.example)',
      description: '=1+1',
      date_preset: 'last_7_days',
      since: 7.days.ago.to_i,
      until: Time.current.to_i,
      widgets: [
        { type: 'metric', metric: 'conversations_count', title: '=HYPERLINK(http://evil.example)', value: 5 },
        { type: 'table', title: 'Tabla', rows: [{ 'name' => '=HYPERLINK(http://evil.example)', 'conversations_count' => 2 }] }
      ]
    }

    xml = xlsx_xml(described_class.new(result).to_xlsx)

    expect(xml[:sheets]).not_to include('<f>')
    expect(xml[:all]).to include('HYPERLINK')
  end
end
