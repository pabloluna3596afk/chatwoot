require 'rails_helper'

RSpec.describe 'Language map' do # rubocop:disable RSpec/DescribeClass
  it 'resolves Norwegian with a string locale code' do
    languages = YAML.load_file(Rails.root.join('config/languages/language_map.yml'))

    expect(languages['no']).to eq('Norwegian')
    expect(languages).not_to have_key(false)
  end
end
