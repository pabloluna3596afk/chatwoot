require 'rails_helper'

RSpec.describe Captain::Assistant::AgentRunResponse do
  let(:host) do
    Class.new do
      include Captain::Assistant::AgentRunResponse

      def initialize(assistant)
        @assistant = assistant
      end

      def result(run_result)
        process_agent_result(run_result)
      end
    end
  end

  it 'logs response size without logging generated customer text' do
    assistant = instance_double(Captain::Assistant, citations_enabled?: false)
    run_result = instance_double(Agents::RunResult, output: { response: 'SECRETO-XYZ-123' }, context: {})
    allow(Rails.logger).to receive(:info)

    host.new(assistant).result(run_result)

    expect(Rails.logger).to have_received(:info).with("[Captain V2] Agent result received (#{run_result.output.to_s.length} chars)")
    expect(Rails.logger).not_to have_received(:info).with(/SECRETO-XYZ-123/)
  end
end
