# Cells that go into CSV / XLSX exports, defused against formula injection.
#
# A spreadsheet app reads a cell that starts with = + - @ (or a tab / carriage return) as a formula, so a
# contact named =HYPERLINK("http://evil") would run when an admin opens the export. Every export of customer
# or user supplied text goes through here, instead of each one remembering to escape on its own.
module Exports::SafeCell
  # What a spreadsheet may take as the start of a formula.
  FORMULA_PREFIX = /\A[=+\-@\t\r]/
  # Same, for columns that are forced to text with a leading tab (a tab alone is harmless there).
  FORMULA_START = /\A[=+\-@\r]/
  # A phone number or a plain number: a leading + or - on these is not an attack, and escaping would break a re-import.
  NUMERIC_LOOKING = /\A[+\-]?[\d\s().\-]+\z/

  module_function

  # The value with a leading apostrophe when it would be read as a formula; anything that is not a String is untouched.
  def value(cell, allow_numeric: false)
    return cell unless cell.is_a?(String) && cell.match?(FORMULA_PREFIX)
    return cell if allow_numeric && cell.match?(NUMERIC_LOOKING)

    "'#{cell}"
  end

  # For columns that must stay text (phone numbers, document numbers): a leading tab stops the app from turning long
  # digit strings into numbers; text that starts like a formula gets the apostrophe instead.
  def text(cell)
    return '' if cell.nil?

    string = cell.to_s
    return '' if string.blank?

    string.match?(FORMULA_START) ? "'#{string}" : "\t#{string}"
  end

  def row(cells, allow_numeric: false)
    Array(cells).map { |cell| value(cell, allow_numeric: allow_numeric) }
  end

  # An Axlsx worksheet whose rows are escaped and whose strings are typed as text (an untyped string that starts
  # with "=" is stored as a formula).
  class Sheet
    def initialize(sheet)
      @sheet = sheet
    end

    # `types` may name a type per column; the columns it leaves nil are typed as text when the cell is a string.
    def add_row(cells, options = {})
      safe = Exports::SafeCell.row(cells)
      given = Array(options[:types])
      types = safe.each_with_index.map { |cell, index| given[index] || (cell.is_a?(String) ? :string : nil) }
      @sheet.add_row(safe, options.merge(types: types))
    end
  end

  def sheet(worksheet)
    Sheet.new(worksheet)
  end
end
