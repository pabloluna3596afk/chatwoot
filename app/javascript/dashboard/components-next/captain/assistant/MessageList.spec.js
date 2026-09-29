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
  });

describe('MessageList', () => {
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
