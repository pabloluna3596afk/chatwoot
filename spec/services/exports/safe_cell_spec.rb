require 'rails_helper'

RSpec.describe Exports::SafeCell do
  describe '.value' do
    it 'prefixes cells that a spreadsheet would read as a formula' do
      ['=1+1', '+cmd', '-cmd', '@SUM(A1)', "\tcmd", "\rcmd"].each do |cell|
        expect(described_class.value(cell)).to eq("'#{cell}")
      end
    end

    it 'leaves ordinary text and non strings alone' do
      expect(described_class.value('Ana Pérez')).to eq('Ana Pérez')
      expect(described_class.value('')).to eq('')
      expect(described_class.value(nil)).to be_nil
      expect(described_class.value(42)).to eq(42)
    end

    it 'keeps plain numbers and phone numbers when asked to (rows written back for a re-import)' do
      expect(described_class.value('+593 (99) 123-4567', allow_numeric: true)).to eq('+593 (99) 123-4567')
      expect(described_class.value('-12.5', allow_numeric: true)).to eq('-12.5')
      expect(described_class.value('+cmd|calc', allow_numeric: true)).to eq("'+cmd|calc")
      expect(described_class.value('=1+1', allow_numeric: true)).to eq("'=1+1")
    end
  end

  describe '.text' do
    it 'forces text with a leading tab, or an apostrophe when the text starts like a formula' do
      expect(described_class.text('0991234567')).to eq("\t0991234567")
      expect(described_class.text('+593991234567')).to eq("'+593991234567")
      expect(described_class.text('=1+1')).to eq("'=1+1")
      expect(described_class.text(nil)).to eq('')
    end
  end

  describe '.sheet' do
    it 'escapes the row and types strings as text, so "=" is never stored as a formula' do
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: 'Test') do |worksheet|
        described_class.sheet(worksheet).add_row(['=HYPERLINK(http://evil.example)', 'plain', 7])
      end

      xml = xlsx_xml(package.to_stream.read)

      expect(xml[:sheets]).not_to include('<f>')
      expect(xml[:all]).to include('HYPERLINK')
    end
  end
end
