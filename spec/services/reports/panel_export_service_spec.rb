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

  describe 'what a sheet shows' do
    def export(widgets)
      result = { name: 'Panel', description: '', date_preset: 'last_7_days', since: 7.days.ago.to_i, until: Time.current.to_i, widgets: widgets }
      xlsx_xml(described_class.new(result).to_xlsx)[:all]
    end

    it 'exports only the columns the panel was configured with, not the whole contact record' do
      rows = [{ 'id' => 1, 'name' => 'Ana Demo', 'phone_number' => '+593990000001', 'email' => 'ana@example.test',
                'document_number' => '1712345678' }]
      xml = export([{ type: 'table', title: 'Contactos', table_kind: 'contacts', columns: %w[name], rows: rows, total_count: 1 }])

      expect(xml).to include('Ana Demo')
      expect(xml).not_to include('+593990000001', 'ana@example.test', '1712345678')
    end

    it 'says a widget failed instead of showing it as empty' do
      xml = export([{ type: 'table', title: 'Con error', error: 'unknown_pivot_attribute', rows: [] }])

      expect(xml).to include('Este widget no se pudo calcular', 'unknown_pivot_attribute')
      expect(xml).not_to include('Sin datos para este periodo')
    end

    it 'says how many records exist when a detail table was cut' do
      rows = [{ 'name' => 'Ana Demo' }]
      xml = export([{ type: 'table', title: 'Contactos', table_kind: 'contacts', columns: %w[name], rows: rows, total_count: 250, truncated: true }])

      expect(xml).to include('Se muestran 1 de 250 registros')
    end

    it 'keeps the columns of a table with no configured columns' do
      xml = export([{ type: 'table', title: 'Agentes', rows: [{ 'name' => 'Ana Demo', 'conversations_count' => 3 }] }])

      expect(xml).to include('Ana Demo', 'Conversaciones')
    end
  end
end
