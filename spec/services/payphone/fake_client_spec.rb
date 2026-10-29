require 'rails_helper'

RSpec.describe Payphone::FakeClient do
  it 'fails at boot when the fake client is enabled in production' do
    initializer = Rails.root.join('config/initializers/payphone_preview.rb')

    with_modified_env('PAYPHONE_PREVIEW_FAKE' => '1') do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect { load initializer }.to raise_error(RuntimeError, /forbidden in production/)
    end
  end
end
