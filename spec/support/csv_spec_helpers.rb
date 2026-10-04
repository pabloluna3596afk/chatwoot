module CsvSpecHelpers
  # The XML of an xlsx file, as { sheets: <worksheets>, all: <everything under xl/> }, to check what a cell was stored as
  # (a formula is a <f> element in the worksheet).
  def xlsx_xml(data)
    parts = { sheets: +'', all: +'' }
    Zip::InputStream.open(StringIO.new(data)) do |zip|
      while (entry = zip.get_next_entry)
        next unless entry.name.start_with?('xl/')

        content = zip.read
        parts[:all] << content
        parts[:sheets] << content if entry.name.start_with?('xl/worksheets/')
      end
    end
    parts
  end

  # Generates a Rack::Test::UploadedFile object from an array of arrays
  # data: Accepts an array of arrays as the only argument
  def generate_csv_file(data)
    # Create a temporary file
    temp_file = Tempfile.new(['data', '.csv'])

    # Write the array of arrays to the temporary file as CSV
    CSV.open(temp_file.path, 'wb') do |csv|
      data.each do |row|
        csv << row
      end
    end

    # Create and return a Rack::Test::UploadedFile object
    Rack::Test::UploadedFile.new(temp_file.path, 'text/csv')
  end
end
