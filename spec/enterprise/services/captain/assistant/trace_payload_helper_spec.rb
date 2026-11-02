require 'rails_helper'
require_relative '../../../../../enterprise/app/services/captain/assistant/trace_content_redaction'

RSpec.describe Captain::Assistant::TracePayloadHelper do
  subject(:helper) { host.new }

  let(:host) do
    Class.new do
      include Captain::Assistant::TracePayloadHelper

      def messages(history)
        serialize_trace_messages(history)
      end

      def content(value)
        serialize_trace_content(value)
      end
    end
  end

  around do |example|
    with_modified_env('LANGFUSE_CAPTURE_CONTENT' => nil) { example.run }
  end

  it 'redacts conversation text in trace input by default' do
    result = helper.messages([{ role: 'user', content: 'SECRETO-XYZ-123' }])

    expect(result).to include('[REDACTED]', 'chars')
    expect(result).not_to include('SECRETO-XYZ-123')
  end

  it 'captures conversation text only when explicitly enabled' do
    result = with_modified_env('LANGFUSE_CAPTURE_CONTENT' => 'true') do
      helper.messages([{ role: 'user', content: 'SECRETO-XYZ-123' }])
    end

    expect(result).to include('SECRETO-XYZ-123')
  end

  it 'redacts content serialized by the AI agent tracing callbacks by default' do
    result = Agents::Instrumentation::TracingCallbacks.allocate.send(:serialize_output, 'SECRETO-XYZ-123')

    expect(result).to include('[REDACTED]', 'chars')
    expect(result).not_to include('SECRETO-XYZ-123')
  end

  it 'allows AI agent tracing callback content only when explicitly enabled' do
    result = with_modified_env('LANGFUSE_CAPTURE_CONTENT' => 'true') do
      Agents::Instrumentation::TracingCallbacks.allocate.send(:serialize_output, 'SECRETO-XYZ-123')
    end

    expect(result).to eq('SECRETO-XYZ-123')
  end
end
