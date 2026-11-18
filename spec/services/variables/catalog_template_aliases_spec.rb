require 'rails_helper'

RSpec.describe Variables::Catalog do
  it 'keeps every template system binding aligned with the server aliases' do
    source = Rails.root.join('app/javascript/dashboard/helper/templateVariableBindings.js').read
    bindings = source.scan(/\{ name: '([^']+)', key: '([^']+)' \}/)

    expect(bindings).not_to be_empty
    bindings.each do |name, key|
      expect(described_class::ALIASES.fetch(key, [])).to include(name), "expected #{key} to include #{name}"
    end
  end
end
