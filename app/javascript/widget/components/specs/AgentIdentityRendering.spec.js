import { mount, shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'widget/i18n/locale/en.json';
import es from 'widget/i18n/locale/es.json';
import AgentMessage from '../AgentMessage.vue';
import UnreadMessage from '../UnreadMessage.vue';

const maliciousName =
  '<img src="https://example.com/tracker.png" onerror="alert(1)">Agent';
const maliciousCompanyName = '<strong>Example Company</strong>';

const channelConfig = {
  avatarUrl: '',
  enabledFeatures: [],
  websiteName: maliciousCompanyName,
};

describe('agent identity rendering', () => {
  beforeEach(() => {
    window.chatwootWebChannel = channelConfig;
  });

  afterEach(() => {
    delete window.chatwootWebChannel;
  });

  it('renders the agent name as plain text beside widget messages', () => {
    const wrapper = shallowMount(AgentMessage, {
      props: {
        message: {
          id: 1,
          attachments: [],
          content: 'Hello',
          content_attributes: {},
          content_type: 'text',
          message_type: 1,
          sender: {
            available_name: maliciousName,
            avatar_url: '',
          },
          showAvatar: true,
        },
      },
    });
    const agentName = wrapper.find('.agent-name');

    expect(agentName.text()).toBe(maliciousName);
    expect(agentName.find('img').exists()).toBe(false);
    expect(agentName.html()).toContain('&lt;img');
  });

  it('renders agent and company names as plain text in unread messages', () => {
    const wrapper = mount(UnreadMessage, {
      props: {
        message: 'Hello',
        showSender: true,
        sender: {
          available_name: maliciousName,
          avatar_url: '',
        },
      },
      global: {
        stubs: { Avatar: true },
        directives: {
          dompurifyHtml: (element, binding) => {
            element.textContent = binding.value;
          },
        },
      },
    });
    const agentName = wrapper.find('.agent--name');
    const companyName = wrapper.find('.company--name');

    expect(agentName.text()).toBe(maliciousName);
    expect(agentName.find('img').exists()).toBe(false);
    expect(companyName.text()).toContain(maliciousCompanyName);
    expect(companyName.find('strong').exists()).toBe(false);
  });
  it.each([
    ['en', [], null, 'System'],
    ['es', [], null, 'Sistema'],
    ['en', ['use_inbox_avatar_for_bot'], null, 'System'],
    ['es', ['use_inbox_avatar_for_bot'], null, 'Sistema'],
    [
      'en',
      [],
      { type: 'agent_bot', name: 'Sales connector' },
      'Sales connector',
    ],
    [
      'es',
      [],
      { type: 'agent_bot', name: 'Conector de ventas' },
      'Conector de ventas',
    ],
  ])(
    'uses the %s identity for messages and unread previews',
    (locale, enabledFeatures, sender, expected) => {
      window.chatwootWebChannel = { ...channelConfig, enabledFeatures };
      const global = {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
        directives: { dompurifyHtml: {} },
      };
      const message = shallowMount(AgentMessage, {
        props: {
          message: {
            id: 1,
            content: 'Hello',
            content_attributes: {},
            message_type: 1,
            sender,
            showAvatar: true,
          },
        },
        global,
      });
      const unread = shallowMount(UnreadMessage, {
        props: { message: 'Hello', showSender: true, sender },
        global,
      });
      expect(message.get('.agent-name').text()).toBe(expected);
      expect(unread.get('.agent--name').text()).toBe(expected);
      message.unmount();
      unread.unmount();
    }
  );
});
