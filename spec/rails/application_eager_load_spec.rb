require 'rails_helper'

# Production boots with eager_load enabled; test does not. Loading every constant here
# catches callback/skip_before_action mistakes that only fail at boot in production.
RSpec.describe Rails::Application, '#eager_load!' do
  it 'eager loads every controller, model and job without raising' do
    expect { Rails.application.eager_load! }.not_to raise_error
  end
end
