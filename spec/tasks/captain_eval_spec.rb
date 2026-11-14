require 'rails_helper'

RSpec.describe 'captain:eval' do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task['captain:eval'] }

  before do
    task.reenable
    allow(Llm::Config).to receive(:api_key_configured?).and_return(true)
  end

  it 'refuses without CAPTAIN_EVAL before calling a provider' do
    with_modified_env CAPTAIN_EVAL: nil do
      expect(Captain::Llm::EmbeddingService).not_to receive(:new)
      expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)
      expect { task.invoke }.to raise_error(Captain::Eval::Runner::Refused, /CAPTAIN_EVAL/)
    end
  end

  it 'refuses in production' do
    with_modified_env CAPTAIN_EVAL: '1' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(Captain::Eval::Sandbox).not_to receive(:new)
      expect { task.invoke }.to raise_error(Captain::Eval::Runner::Refused, /desarrollo/)
    end
  end

  it 'refuses without a configured AI key' do
    with_modified_env CAPTAIN_EVAL: '1', CI: nil do
      allow(Llm::Config).to receive(:api_key_configured?).and_return(false)
      expect(Captain::Eval::Sandbox).not_to receive(:new)
      expect { task.invoke }.to raise_error(Captain::Eval::Runner::Refused, /clave de IA/)
    end
  end

  it 'refuses in CI' do
    with_modified_env CAPTAIN_EVAL: '1', CI: 'true' do
      expect(Captain::Eval::Sandbox).not_to receive(:new)
      expect { task.invoke }.to raise_error(Captain::Eval::Runner::Refused, /CI/)
    end
  end

  it 'prints the generated report paths' do
    with_modified_env CAPTAIN_EVAL: '1', CI: nil do
      runner = instance_double(Captain::Eval::Runner, perform: { markdown: 'report.md', json: 'report.json', totals: { total: 30 } })
      allow(Captain::Eval::Runner).to receive(:new).and_return(runner)
      expect { task.invoke }.to output(/report.md.*report.json/m).to_stdout
    end
  end
end
