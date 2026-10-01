require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar::EventLock do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:other_user) { create(:user, account: account) }
  let(:event_id) { 'event-lock-1' }
  let(:lock) { described_class.new(account_id: account.id, event_id: event_id) }

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: event_id)) }

  it 'lets the holder re-acquire and refresh the lock' do
    expect(lock.acquire(user)[:ok]).to be(true)
    expect(lock.acquire(user)[:ok]).to be(true)
    expect(lock.heartbeat(user)[:ok]).to be(true)
  end

  it 'blocks another user and reports the holder' do
    lock.acquire(user)
    result = lock.acquire(other_user)

    expect(result[:ok]).to be(false)
    expect(result[:holder]).to include('user_id' => user.id, 'name' => user.name)
  end

  it 'only lets the holder release the lock' do
    lock.acquire(user)

    expect(lock.release(other_user)).to be(false)
    expect(lock.holder).to be_present
    expect(lock.release(user)).to be(true)
    expect(lock.holder).to be_nil
  end

  describe 'when an AgentBot calls the service' do
    # EventService passes the AgentBot as `user` for Panel AI bridge requests, and the lock
    # identifies holders by `user.id` only. AgentBot ids and User ids come from different tables.
    let(:colliding_bot) { create(:agent_bot, id: user.id, account: account) }

    it 'does not treat a bot with the same numeric id as the user holding the lock' do
      lock.acquire(user)

      expect(lock.acquire(colliding_bot)[:ok]).to be(false)
      expect(lock.heartbeat(colliding_bot)[:ok]).to be(false)
      expect(lock.release(colliding_bot)).to be(false)
      expect(lock.holder).to include('holder_key' => "User:#{user.id}")
    end

    it 'does not let the user take over the lock of a bot with the same id' do
      lock.acquire(colliding_bot)

      expect(lock.acquire(user)[:ok]).to be(false)
      expect(lock.holder).to include('holder_key' => "AgentBot:#{colliding_bot.id}", 'name' => colliding_bot.name)
    end

    it 'lets the same bot re-acquire its own lock' do
      expect(lock.acquire(colliding_bot)[:ok]).to be(true)
      expect(lock.acquire(colliding_bot)[:ok]).to be(true)
    end
  end

  describe 'a lock written before holder_key existed' do
    let(:key) { format(Redis::RedisKeys::CALENDAR_EVENT_LOCK, account_id: account.id, event_id: event_id) }

    before { Redis::Alfred.setex(key, { user_id: user.id, name: user.name }.to_json, 180) }

    it 'still belongs to the User with that id' do
      expect(lock.acquire(user)[:ok]).to be(true)
      expect(lock.acquire(other_user)[:ok]).to be(false)
      expect(lock.holder).to include('name' => user.name, 'holder_key' => "User:#{user.id}")
    end

    it 'is not taken over by a bot with the same id' do
      expect(lock.acquire(create(:agent_bot, id: user.id, account: account))[:ok]).to be(false)
    end
  end
end
