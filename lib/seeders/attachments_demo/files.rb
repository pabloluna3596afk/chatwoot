require 'open3'
require 'tmpdir'
require 'zip'

class Seeders::AttachmentsDemo::Files
  FIXTURES = Rails.root.join('spec/assets/attachments_demo').freeze
  IMAGES = {
    'normal.png' => ['photo.jpg', '-resize', '640x480!'],
    'photo.jpg' => ['photo.jpg'], 'animated.gif' => ['photo.jpg', 'receipt.png', '-resize', '240x240!', '-set', 'delay', '60', '-loop', '0'],
    'image.webp' => ['photo.jpg'], 'tall.png' => ['receipt.png', '-resize', '2000x6000!'],
    'wide.png' => ['photo.jpg', '-resize', '3000x600!'], 'tiny.png' => ['photo.jpg', '-resize', '40x40!'],
    'receipt.png' => ['receipt.png'],
    'sticker.webp' => ['-size', '160x160', 'xc:none', '-fill', '#2781f6', '-draw', 'circle 80,80 80,20']
  }.freeze
  OFFICE_TYPES = {
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  }.freeze

  def initialize(directory)
    @directory = directory
    @blobs = {}
  end

  def blob(name)
    @blobs[name] ||= begin
      path = generate(name)
      File.open(path) do |io|
        ActiveStorage::Blob.create_and_upload!(io: io, filename: name, content_type: content_type(name), identify: false,
                                               service_name: Rails.env.test? ? 'test' : 'local',
                                               metadata: { analyzed: true, identified: true }.merge(dimensions(name)))
      end
    end
  end

  private

  def generate(name)
    path = File.join(@directory, name)
    if IMAGES.key?(name)
      image(name, path)
    elsif %w[audio.mp3 voice.ogg video.mp4].include?(name)
      FileUtils.cp(FIXTURES.join(name), path)
    elsif name.end_with?('.pdf')
      File.binwrite(path, pdf(large: name == 'large.pdf'))
    elsif name.end_with?('.docx', '.xlsx', '.zip')
      archive(path, File.extname(name).delete_prefix('.'))
    else
      File.write(path, "Adjuntos demo: local attachment fixture.\n")
    end
    path
  end

  def image(name, path)
    arguments = IMAGES.fetch(name).map { |argument| File.exist?(FIXTURES.join(argument)) ? FIXTURES.join(argument).to_s : argument }
    _output, error, status = Open3.capture3('convert', *arguments, path)
    raise "ImageMagick could not generate #{name}: #{error}" unless status.success?
  end

  def dimensions(name)
    return {} unless IMAGES.key?(name)

    output, = Open3.capture2('identify', '-format', '%w %h', "#{File.join(@directory, name)}[0]")
    width, height = output.split.map(&:to_i)
    { width: width, height: height }
  end

  def content_type(name)
    OFFICE_TYPES.fetch(File.extname(name).delete_prefix('.')) { Marcel::MimeType.for(name: name) }
  end

  # Three real pages, an uncompressed content stream for the large-file scenario,
  # and a proper cross-reference table, without a runtime PDF-writing dependency.
  def pdf(large:)
    objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [4 0 R 6 0 R 8 0 R] /Count 3 >>',
               '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    3.times do |index|
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents #{5 + (index * 2)} 0 R >>"
      stream = "BT /F1 24 Tf 50 750 Td (Adjuntos demo - page #{index + 1} of 3) Tj ET\n"
      stream << ("% local demo padding #{'x' * 100}\n" * 45_000) if large && index.zero?
      objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}endstream"
    end
    serialize_pdf(objects)
  end

  def serialize_pdf(objects)
    result = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |object, index|
      offset = result.bytesize
      result << "#{index + 1} 0 obj\n#{object}\nendobj\n"
      offset
    end
    start = result.bytesize
    result << "xref\n0 #{objects.length + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| result << format("%010d 00000 n \n", offset) }
    result << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\nstartxref\n#{start}\n%%EOF\n"
  end

  def archive(path, extension)
    entries = case extension
              when 'docx' then word_entries
              when 'xlsx' then excel_entries
              else { 'readme.txt' => 'Local attachments demo ZIP' }
              end
    Zip::OutputStream.open(path) do |zip|
      entries.each do |name, contents|
        zip.put_next_entry(name)
        zip.write(contents)
      end
    end
  end

  def office_entries(part, type)
    {
      '[Content_Types].xml' => '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' \
                               '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
                               "<Override PartName=\"/#{part}\" " \
                               "ContentType=\"application/vnd.openxmlformats-officedocument.#{type}.main+xml\"/></Types>",
      '_rels/.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
                       '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" ' \
                       "Target=\"#{part}\"/></Relationships>"
    }
  end

  def word_entries
    office_entries('word/document.xml', 'wordprocessingml.document').merge(
      'word/document.xml' => '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' \
                             '<w:body><w:p><w:r><w:t>Adjuntos demo - contrato local</w:t></w:r></w:p></w:body></w:document>'
    )
  end

  def excel_entries
    office_entries('xl/workbook.xml', 'spreadsheetml.sheet').merge(
      'xl/workbook.xml' => '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' \
                           'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' \
                           '<sheets><sheet name="Demo" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
                                      '<Relationship Id="rId1" ' \
                                      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ' \
                                      'Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml' => '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
                                    '<sheetData><row r="1"><c r="A1"><v>120</v></c></row></sheetData></worksheet>'
    ).tap do |entries|
      entries['[Content_Types].xml'].sub!('</Types>', '<Override PartName="/xl/worksheets/sheet1.xml" ' \
                                                      'ContentType="application/vnd.openxmlformats-officedocument.' \
                                                      'spreadsheetml.worksheet+xml"/></Types>')
    end
  end
end
