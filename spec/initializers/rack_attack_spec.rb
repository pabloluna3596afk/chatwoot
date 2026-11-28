require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
describe 'Rack::Attack auth throttles' do
  let(:ip) { '203.0.113.7' }

  def throttle_key(name, env)
    Rack::Attack.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
  end

  def build_env(path, body, content_type, method: 'POST')
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'SCRIPT_NAME' => '',
      'QUERY_STRING' => '',
      'CONTENT_TYPE' => content_type,
      'CONTENT_LENGTH' => body.bytesize.to_s,
      'REMOTE_ADDR' => ip,
      'rack.input' => StringIO.new(body),
      'rack.url_scheme' => 'http',
      'action_dispatch.remote_ip' => ip
    }
  end

  def json_env(body, path = '/auth/sign_in')
    build_env(path, body.to_json, 'application/json')
  end

  def form_env(params, path = '/auth/sign_in')
    build_env(path, Rack::Utils.build_nested_query(params), 'application/x-www-form-urlencoded')
  end

  describe 'login/ip' do
    it 'counts form-encoded password sign-ins by ip' do
      expect(throttle_key('login/ip', form_env({ 'email' => 'a@b.com', 'password' => 'x' }))).to eq(ip)
    end

    it 'counts JSON password sign-ins by ip' do
      expect(throttle_key('login/ip', json_env({ email: 'a@b.com', password: 'x' }))).to eq(ip)
    end

    it 'skips form-encoded verification submissions carrying mfa_token' do
      expect(throttle_key('login/ip', form_env({ 'mfa_token' => 'tok', 'otp_code' => '123456' }))).to be_nil
    end

    it 'skips JSON verification submissions carrying mfa_token' do
      expect(throttle_key('login/ip', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to be_nil
    end
  end

  describe 'public plan catalog safelist' do
    it 'bypasses shared-IP throttles for GET requests to the catalog only' do
      catalog_request = Rack::Attack::Request.new(build_env('/public/api/v1/plans', '', '', method: 'GET'))
      another_public_request = Rack::Attack::Request.new(build_env('/public/api/v1/csat_survey', '', '', method: 'GET'))
      catalog_preflight = Rack::Attack::Request.new(build_env('/public/api/v1/plans', '', '', method: 'OPTIONS'))

      safelist = Rack::Attack.safelists.fetch('public plan catalog')
      expect(safelist.block.call(catalog_request)).to be(true)
      expect(safelist.block.call(catalog_preflight)).to be(true)
      expect(safelist.block.call(another_public_request)).to be(false)
    end
  end

  describe 'login/email' do
    it 'keys JSON password sign-ins by normalized email' do
      key = throttle_key('login/email', json_env({ email: ' User@Example.COM ', password: 'x' }))
      expect(key).to eq('user@example.com')
    end

    it 'keys sign-ins that pass the email via request header' do
      env = build_env('/auth/sign_in', '{"password":"x"}', 'application/json')
      env['HTTP_EMAIL'] = ' User@Example.COM '
      expect(throttle_key('login/email', env)).to eq('user@example.com')
    end

    it 'skips JSON verification submissions carrying mfa_token' do
      expect(throttle_key('login/email', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to be_nil
    end

    it 'skips requests without an email instead of sharing a blank key' do
      expect(throttle_key('login/email', json_env({ otp_code: '123456' }))).to be_nil
    end

    it 'skips a non-string email instead of raising a 500' do
      expect(throttle_key('login/email', json_env({ email: ['a@b.com'], password: 'x' }))).to be_nil
    end

    it 'skips malformed JSON bodies without raising' do
      env = build_env('/auth/sign_in', '{"email": broken', 'application/json')
      expect(throttle_key('login/email', env)).to be_nil
    end
  end

  describe 'super_admin_login/ip' do
    it 'counts password sign-ins by ip' do
      env = form_env({ 'super_admin' => { 'email' => 'a@b.com', 'password' => 'x' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_login/ip', env)).to eq(ip)
    end

    it 'skips code submissions' do
      env = form_env({ 'super_admin' => { 'otp_code' => '123456' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_login/ip', env)).to be_nil
    end

    it 'counts a JSON sign-in with a null code as a password sign-in' do
      env = json_env({ super_admin: { email: 'a@b.com', password: 'x', otp_code: nil } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_login/ip', env)).to eq(ip)
    end
  end

  describe 'super_admin_mfa/ip' do
    it 'counts code submissions by ip' do
      env = form_env({ 'super_admin' => { 'otp_code' => '123456' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_mfa/ip', env)).to eq(ip)
    end

    it 'skips password sign-ins' do
      env = form_env({ 'super_admin' => { 'email' => 'a@b.com', 'password' => 'x' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_mfa/ip', env)).to be_nil
    end
  end

  describe 'super_admin_login/email' do
    it 'keys password sign-ins by the normalized super admin email' do
      env = form_env({ 'super_admin' => { 'email' => ' Admin@Example.COM ', 'password' => 'x' } }, '/super_admin/sign_in')
      key = throttle_key('super_admin_login/email', env)
      expect(key).to eq('admin@example.com')
    end

    it 'keys JSON password sign-ins by the normalized super admin email' do
      env = json_env({ super_admin: { email: ' Admin@Example.COM ', password: 'x' } }, '/super_admin/sign_in')
      expect(throttle_key('super_admin_login/email', env)).to eq('admin@example.com')
    end

    it 'skips malformed JSON bodies without raising' do
      env = build_env('/super_admin/sign_in', '{"super_admin": broken', 'application/json')
      expect(throttle_key('super_admin_login/email', env)).to be_nil
    end

    it 'skips code submissions instead of sharing a blank key' do
      expect(throttle_key('super_admin_login/email', form_env({ 'super_admin' => { 'otp_code' => '123456' } }, '/super_admin/sign_in'))).to be_nil
    end

    it 'skips a non-hash super_admin param' do
      expect(throttle_key('super_admin_login/email', form_env({ 'super_admin' => 'email' }, '/super_admin/sign_in'))).to be_nil
    end
  end

  describe 'malformed query strings' do
    it 'falls back to the per-ip throttle instead of raising on an over-nested query' do
      env = build_env('/auth/sign_in', '{}', 'application/json')
      env['QUERY_STRING'] = "a#{'[b]' * 200}=x"
      expect(throttle_key('login/ip', env)).to eq(ip)
    end
  end

  describe 'mfa_login/ip' do
    it 'counts JSON verification submissions by ip' do
      expect(throttle_key('mfa_login/ip', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to eq(ip)
    end
  end

  describe 'mfa_login/token' do
    it 'keys JSON verification submissions by token' do
      expect(throttle_key('mfa_login/token', json_env({ mfa_token: 'tok', otp_code: '123456' }))).to eq('tok')
    end
  end

  describe 'reset_password/email' do
    it 'keys JSON requests by normalized email' do
      key = throttle_key('reset_password/email', json_env({ email: ' User@Example.COM ' }, '/auth/password'))
      expect(key).to eq('user@example.com')
    end

    it 'skips requests without an email instead of sharing a blank key' do
      expect(throttle_key('reset_password/email', json_env({ redirect_url: '/' }, '/auth/password'))).to be_nil
    end

    it 'ignores the email header, which this endpoint does not honor' do
      env = build_env('/auth/password', '{}', 'application/json')
      env['HTTP_EMAIL'] = 'victim@example.com'
      expect(throttle_key('reset_password/email', env)).to be_nil
    end
  end

  describe 'resend_confirmation/email' do
    it 'skips requests without an email instead of sharing a blank key' do
      expect(throttle_key('resend_confirmation/email', json_env({}, '/resend_confirmation'))).to be_nil
    end
  end

  describe 'conversation list and filter throttles' do
    it 'uses separate buckets for each user and account for both list and filter' do
      %w[conversations conversations/filter].each do |route|
        name = "/api/v1/accounts/:account_id/#{route}/user"
        method = route.end_with?('filter') ? 'POST' : 'GET'
        env = Rack::MockRequest.env_for("/api/v1/accounts/1/#{route}", method: method, 'HTTP_UID' => 'user-1')
        expect(throttle_key(name, env)).to eq('user-1:1')
        expect(throttle_key(name, env.merge('HTTP_UID' => 'user-2'))).to eq('user-2:1')
        expect(throttle_key(name, env.merge('PATH_INFO' => "/api/v1/accounts/2/#{route}"))).to eq('user-1:2')
        expect(throttle_key(name, env.except('HTTP_UID'))).to be_nil
      end
    end

    it 'honors bearer tokens ahead of spoofed uid and supports API access tokens' do
      name = '/api/v1/accounts/:account_id/conversations/user'
      env = Rack::MockRequest.env_for('/api/v1/accounts/1/conversations', 'HTTP_UID' => 'user-1', 'HTTP_API_ACCESS_TOKEN' => 'api-token')
      expect(throttle_key(name, env)).to eq('user-1:1')
      expect(throttle_key(name, env.except('HTTP_UID'))).to eq('api-token:1')
      expect(throttle_key(name, env.merge('HTTP_AUTHORIZATION' => 'Bearer bearer-token'))).to eq('bearer-token:1')
    end

    it 'keeps bulk actions and exports out of the list and filter throttles' do
      %w[bulk_actions conversations/bulk_actions conversations/export].each do |route|
        env = Rack::MockRequest.env_for("/api/v1/accounts/1/#{route}", method: 'POST', 'HTTP_UID' => 'user-1')
        expect(throttle_key('/api/v1/accounts/:account_id/conversations/user', env)).to be_nil
        expect(throttle_key('/api/v1/accounts/:account_id/conversations/filter/user', env)).to be_nil
      end
    end

    it 'keys the conversation list by the bearer API token' do
      env = Rack::MockRequest.env_for('/api/v1/accounts/1/conversations?page=2', 'HTTP_AUTHORIZATION' => 'Bearer api-token')
      expect(throttle_key('/api/v1/accounts/:account_id/conversations/user', env)).to eq('api-token:1')
    end

    it 'keeps other conversation routes and conversation creation out of the list throttle' do
      name = '/api/v1/accounts/:account_id/conversations/user'
      headers = { 'HTTP_AUTHORIZATION' => 'Bearer api-token' }
      %w[/api/v1/accounts/1/conversations/meta /api/v1/accounts/1/conversations/5 /api/v1/accounts/1/contacts/5/conversations].each do |path|
        expect(throttle_key(name, Rack::MockRequest.env_for(path, headers))).to be_nil
      end
      expect(throttle_key(name, Rack::MockRequest.env_for('/api/v1/accounts/1/conversations', headers.merge(method: 'POST')))).to be_nil
    end

    it 'keys the conversation filter by the bearer API token' do
      env = Rack::MockRequest.env_for('/api/v1/accounts/1/conversations/filter?page=2', method: 'POST', 'HTTP_AUTHORIZATION' => 'Bearer api-token')
      expect(throttle_key('/api/v1/accounts/:account_id/conversations/filter/user', env)).to eq('api-token:1')
    end

    it 'keeps other filter routes and non-POST requests out of the conversation filter throttle' do
      name = '/api/v1/accounts/:account_id/conversations/filter/user'
      headers = { method: 'POST', 'HTTP_AUTHORIZATION' => 'Bearer api-token' }
      %w[/api/v1/accounts/1/contacts/filter /api/v1/accounts/1/conversations /api/v1/accounts/1/conversations/5].each do |path|
        expect(throttle_key(name, Rack::MockRequest.env_for(path, headers))).to be_nil
      end
      expect(throttle_key(name, Rack::MockRequest.env_for('/api/v1/accounts/1/conversations/filter', headers.merge(method: 'GET')))).to be_nil
    end
  end

  describe 'throttle event logging' do
    it 'logs which rule matched' do
      env = form_env({ 'email' => 'a@b.com', 'password' => 'x' })
      env['rack.attack.matched'] = 'login/ip'
      request = Rack::Attack::Request.new(env)

      expect(Rails.logger).to receive(:warn).with(a_string_including('matched_rule: "login/ip"'))
      ActiveSupport::Notifications.instrument('throttle.rack_attack', request: request)
    end
  end
end

# rubocop:enable RSpec/DescribeClass
