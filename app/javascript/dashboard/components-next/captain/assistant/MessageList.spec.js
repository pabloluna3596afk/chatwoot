import { ASSISTANT_NAME_MARKER } from 'dashboard/composables/useAssistantName';
import { shallowMount } from '@vue/test-utils';
import MessageList from './MessageList.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('shared/composables/useMessageFormatter', () => ({
  useMessageFormatter: () => ({ formatMessage: text => text }),
}));

const mountList = (props = {}) =>
  shallowMount(MessageList, {
    props: {
      messages: [
        { sender: 'user', content: 'Hello' },
        { sender: 'assistant', content: 'Hi there' },
      ],
      assistant: {
        name: 'Acme assistant',
        avatar_url: 'https://example.com/acme.png',
      },
      ...props,
    },
    global: { stubs: { AssistantNameText: false } },
  });

describe('MessageList', () => {
  it('renders local error copy as text and a name span without leaking the sentinel', () => {
    const wrapper = mountList({
      messages: [
        {
          sender: 'assistant',
          isError: true,
          nameRichText: true,
          content: `${ASSISTANT_NAME_MARKER}Aurora${ASSISTANT_NAME_MARKER} no pudo completar <esta prueba>.`,
        },
      ],
    });
    expect(wrapper.text()).toBe('Aurora no pudo completar <esta prueba>.');
    expect(wrapper.get('.assistant-name').attributes('title')).toBe('Aurora');
    expect(wrapper.html()).not.toContain(ASSISTANT_NAME_MARKER);
    expect(wrapper.find('esta').exists()).toBe(false);
    wrapper.unmount();
  });

  it('shows the assistant photo on assistant messages only', () => {
    const avatars = mountList().findAllComponents({ name: 'Avatar' });

    expect(avatars).toHaveLength(2);
    expect(avatars[0].props('src')).toBe('');
    expect(avatars[0].props('name')).toBe('CAPTAIN.PLAYGROUND.USER');
    expect(avatars[1].props('src')).toBe('https://example.com/acme.png');
    expect(avatars[1].props('name')).toBe('Acme assistant');
  });

  it('uses the assistant photo on the typing indicator', () => {
    const avatars = mountList({ isLoading: true }).findAllComponents({
      name: 'Avatar',
    });

    expect(avatars).toHaveLength(3);
    expect(avatars[2].props('src')).toBe('https://example.com/acme.png');
  });

  it('falls back to the generic assistant label without an assistant', () => {
    const avatars = mountList({ assistant: null }).findAllComponents({
      name: 'Avatar',
    });

    expect(avatars[1].props('src')).toBe('');
    expect(avatars[1].props('name')).toBe('CAPTAIN.PLAYGROUND.ASSISTANT');
  });
});
