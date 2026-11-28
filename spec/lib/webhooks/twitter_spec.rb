require 'rails_helper'
require 'webhooks/twitter'

describe Webhooks::Twitter do
  subject(:twitter_webhook) { described_class }

  let!(:account) { create(:account) }
  # FIX ME: recipient id is set to 1 inside event factories
  let!(:twitter_channel) { create(:channel_twitter_profile, account: account, profile_id: '1', tweets_enabled: true) }
  let!(:twitter_inbox) { create(:inbox, channel: twitter_channel, account: account, greeting_enabled: false) }
  let!(:dm_params) { build(:twitter_message_create_event).with_indifferent_access }
  let!(:dm_image_params) { build(:twitter_dm_image_event).with_indifferent_access }
  let!(:tweet_params) { build(:tweet_create_event).with_indifferent_access }
  let!(:tweet_params_from_blocked_user) { build(:tweet_create_event, user_has_blocked: true).with_indifferent_access }

  describe '#perform' do
    context 'with direct_message params' do
      it 'creates incoming message in the twitter inbox' do
        twitter_webhook.new(dm_params).consume
        expect(twitter_inbox.contacts.count).to be 1
        expect(twitter_inbox.conversations.count).to be 1
        expect(twitter_inbox.messages.count).to be 1
      end
    end

    context 'with direct_message attachment params' do
      let!(:media_request) do
        stub_request(:get, 'https://pbs.twimg.com/media/DOhM30VVwAEpIHq.jpg')
          .with(headers: { 'Authorization' => /\AOAuth / })
          .to_return(status: 200, body: 'image', headers: { 'Content-Type' => 'image/jpeg' })
      end

      before do
        allow(Resolv).to receive(:getaddresses).and_call_original
        allow(Resolv).to receive(:getaddresses).with('pbs.twimg.com').and_return(['93.184.216.34'])
        allow(Resolv).to receive(:getaddresses).with('ton.twitter.com').and_return(['93.184.216.34'])
      end

      it 'creates incoming message with attachments in the twitter inbox' do
        twitter_webhook.new(dm_image_params).consume
        expect(twitter_inbox.contacts.count).to be 1
        expect(twitter_inbox.conversations.count).to be 1
        expect(twitter_inbox.messages.count).to be 1
        expect(twitter_inbox.messages.last.attachments.count).to be 1
        expect(media_request).to have_been_requested
      end

      it 'does not download media from hosts other than twitter media hosts' do
        other_request = stub_request(:get, 'https://example.com/image.jpg').to_return(status: 200, body: 'image')
        dm_image_params[:direct_message_events][0][:message_create][:message_data][:attachment][:media].merge!(
          media_url: 'https://example.com/image.jpg', media_url_https: 'https://example.com/image.jpg'
        )

        twitter_webhook.new(dm_image_params).consume

        expect(twitter_inbox.messages.count).to be 1
        expect(twitter_inbox.messages.last.attachments.count).to be 0
        expect(other_request).not_to have_been_requested
      end

      it 'does not download media over plain http' do
        http_request = stub_request(:get, 'http://pbs.twimg.com/media/DOhM30VVwAEpIHq.jpg').to_return(status: 200, body: 'image')
        dm_image_params[:direct_message_events][0][:message_create][:message_data][:attachment][:media].delete(:media_url_https)

        twitter_webhook.new(dm_image_params).consume

        expect(twitter_inbox.messages.last.attachments.count).to be 0
        expect(http_request).not_to have_been_requested
      end

      [
        'https://pbs.twimg.com.example.com/image.jpg',
        'https://user@pbs.twimg.com/image.jpg',
        'https://pbs.twimg.com:8443/image.jpg',
        'not a url'
      ].each do |url|
        it "does not fetch an unsafe media URL: #{url}" do
          dm_image_params[:direct_message_events][0][:message_create][:message_data][:attachment][:media][:media_url_https] = url

          twitter_webhook.new(dm_image_params).consume

          expect(twitter_inbox.messages.count).to be 1
          expect(twitter_inbox.messages.last.attachments).to be_empty
          expect(a_request(:any, /.*/)).not_to have_been_made
        end
      end

      it 'uses an HTTPS media_url on the other allowed host when media_url_https is missing' do
        request = stub_request(:get, 'https://ton.twitter.com/image.jpg')
                  .with(headers: { 'Authorization' => /\AOAuth / })
                  .to_return(status: 200, body: 'image', headers: { 'Content-Type' => 'image/jpeg' })
        media = dm_image_params[:direct_message_events][0][:message_create][:message_data][:attachment][:media]
        media.delete(:media_url_https)
        media[:media_url] = 'https://ton.twitter.com/image.jpg'

        twitter_webhook.new(dm_image_params).consume

        expect(twitter_inbox.messages.last.attachments.count).to be 1
        expect(request).to have_been_requested.once
      end

      it 'does not forward OAuth credentials when the media host redirects elsewhere' do
        allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
        stub_request(:get, 'https://pbs.twimg.com/media/DOhM30VVwAEpIHq.jpg')
          .to_return(status: 302, headers: { 'Location' => 'https://example.com/image.jpg' })
        redirected_authorization = :not_requested
        stub_request(:get, 'https://example.com/image.jpg')
          .with do |request|
            redirected_authorization = request.headers['Authorization']
            true
          end
          .to_return(status: 200, body: 'image', headers: { 'Content-Type' => 'image/jpeg' })

        twitter_webhook.new(dm_image_params).consume

        expect(twitter_inbox.messages.last.attachments.count).to be 1
        expect(redirected_authorization).to be_nil
      end
    end

    context 'with tweet_params params' do
      it 'does not create incoming message in the twitter inbox if it is a blocked user' do
        twitter_webhook.new(tweet_params_from_blocked_user).consume
        expect(twitter_inbox.contacts.count).to be 0
        expect(twitter_inbox.conversations.count).to be 0
        expect(twitter_inbox.messages.count).to be 0
      end

      it 'creates incoming message in the twitter inbox' do
        twitter_webhook.new(tweet_params).consume
        twitter_inbox.reload
        expect(twitter_inbox.contacts.count).to be 1
        expect(twitter_inbox.conversations.count).to be 1
        expect(twitter_inbox.messages.count).to be 1
      end
    end

    context 'with tweet_enabled flag disabled' do
      before do
        twitter_channel.update(tweets_enabled: false)
      end

      it 'does not create incoming message in the twitter inbox for tweet' do
        twitter_webhook.new(tweet_params).consume
        expect(twitter_inbox.contacts.count).to be 0
        expect(twitter_inbox.conversations.count).to be 0
        expect(twitter_inbox.messages.count).to be 0
      end

      it 'creates incoming message in the twitter inbox' do
        twitter_webhook.new(dm_params).consume
        expect(twitter_inbox.contacts.count).to be 1
        expect(twitter_inbox.conversations.count).to be 1
        expect(twitter_inbox.messages.count).to be 1
      end
    end
  end
end
