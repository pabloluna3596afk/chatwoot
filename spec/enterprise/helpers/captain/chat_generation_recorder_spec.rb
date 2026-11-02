require 'rails_helper'

RSpec.describe Captain::ChatGenerationRecorder do
  let(:host) do
    Class.new do
      include Captain::ChatGenerationRecorder

      def model = 'gpt-4o-mini'

      def temperature = 0.5

      def determine_provider(_model) = 'openai'

      def attributes(chat, message)
        generation_attributes(chat, message)
      end
    end
  end
  let(:secret) { 'SECRETO-XYZ-123' }
  let(:tokens) { Struct.new(:input, :output).new(10, 5) }
  let(:message) { Struct.new(:role, :tokens, :content, :tool_calls).new('assistant', tokens, secret, []) }
  let(:chat_message) { Struct.new(:role, :content).new('user', secret) }
  let(:chat) { Struct.new(:messages).new([chat_message, message]) }

  around do |example|
    with_modified_env('LANGFUSE_CAPTURE_CONTENT' => nil) { example.run }
  end

  it 'redacts generation input and output by default' do
    attributes = host.new.attributes(chat, message)

    expect(attributes['langfuse.observation.input']).to include('[REDACTED]', 'chars')
    expect(attributes['langfuse.observation.output']).to include('[REDACTED]', 'chars')
    expect(attributes.values.join).not_to include(secret)
  end

  it 'captures generation input and output only when explicitly enabled' do
    attributes = with_modified_env('LANGFUSE_CAPTURE_CONTENT' => 'true') do
      host.new.attributes(chat, message)
    end

    expect(attributes['langfuse.observation.input']).to include(secret)
    expect(attributes['langfuse.observation.output']).to eq(secret)
  end
end
