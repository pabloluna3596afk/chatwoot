require 'rails_helper'

RSpec.describe Captain::Assistant::TransientErrors do
  let(:conversation_id) { 123 }

  after { described_class.reset!(conversation_id) }

  it 'matches a Faraday timeout' do
    expect(described_class.match?(Faraday::TimeoutError.new)).to be true
  end

  it 'matches an error whose cause is a rate limit' do
    error = StandardError.new
    allow(error).to receive(:cause).and_return(RubyLLM::RateLimitError.new)

    expect(described_class.match?(error)).to be true
  end

  it 'does not match an ArgumentError' do
    expect(described_class.match?(ArgumentError.new)).to be false
  end

  it 'does not loop on a self-referencing cause' do
    error = StandardError.new
    allow(error).to receive(:cause).and_return(error)

    expect(described_class.match?(error)).to be false
  end

  it 'is not retryable once a side-effect tool ran' do
    described_class.mark_side_effect!(conversation_id)

    expect(described_class.retryable?(Faraday::TimeoutError.new, conversation_id)).to be false
  end

  it 'resolves only the classes that exist' do
    names = described_class::CLASS_NAMES.grep(/\A(?:Faraday|Net|Timeout|Errno)::/)

    expect(names.map(&:safe_constantize)).to all(be_a(Class))
    expect(described_class.classes).to eq(described_class::CLASS_NAMES.filter_map(&:safe_constantize))
  end

  it 'shares the side-effect mark across tool threads and resets it for the next attempt' do
    Thread.new { described_class.mark_side_effect!(conversation_id) }.join

    expect(described_class.retryable?(Faraday::TimeoutError.new, conversation_id)).to be false
    described_class.reset!(conversation_id)
    expect(described_class.retryable?(Faraday::TimeoutError.new, conversation_id)).to be true
  end

  it 'isolates side-effect marks by conversation' do
    described_class.mark_side_effect!(conversation_id)

    expect(described_class.retryable?(Faraday::TimeoutError.new, conversation_id + 1)).to be true
  end

  it 'does not mark or retry a generation without a conversation' do
    described_class.mark_side_effect!(nil)

    expect(described_class).not_to be_side_effect_ran(nil)
    expect(described_class.retryable?(Faraday::TimeoutError.new, nil)).to be false
  end
end
