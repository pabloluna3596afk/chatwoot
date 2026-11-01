require 'rails_helper'

RSpec.describe Captain::ChatHelper do
  let(:host) do
    Class.new do
      include Captain::ChatHelper

      def initialize
        @assistant = Struct.new(:id).new(123)
        @messages = [{ role: 'user', content: 'SECRETO-XYZ-123' }]
        @tools = []
      end

      def log_request
        log_chat_completion_request
      end
    end
  end

  it 'logs message counts and sizes without customer text' do
    allow(Rails.logger).to receive(:info)

    host.new.log_request

    expect(Rails.logger).to have_received(:info).with(/messages=1 content_chars=15 tools=0/)
    expect(Rails.logger).not_to have_received(:info).with(/SECRETO-XYZ-123/)
  end
end
