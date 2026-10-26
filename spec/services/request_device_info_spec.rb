require 'rails_helper'

RSpec.describe RequestDeviceInfo do
  it 'uses the mobile app headers for device metadata' do
    request = Struct.new(:headers, :user_agent).new(
      {
        'X-Chatwoot-Client-Name' => 'Chatwoot Mobile',
        'X-Chatwoot-Platform' => 'iOS',
        'X-Chatwoot-Device-Model' => 'iPhone 17',
        'X-Chatwoot-Client-Version' => '4.19.1'
      },
      'Chatwoot/4.19.1'
    )

    device_info = described_class.new(request)

    expect(device_info.browser_name).to eq('Chatwoot Mobile')
    expect(device_info.platform_label).to eq('iPhone')
    expect(device_info.to_h[:browser_version]).to eq('4.19.1')
  end
end
