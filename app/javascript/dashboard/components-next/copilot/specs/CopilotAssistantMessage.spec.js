import { mount } from '@vue/test-utils';
import CopilotAssistantMessage from '../CopilotAssistantMessage.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useAlert, useTrack } from 'dashboard/composables';

const clipboard = vi.hoisted(() => ({ copy: vi.fn() }));
const copilotMocks = vi.hoisted(() => ({ emitter: { emit: vi.fn() } }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: clipboard.copy,
}));
vi.mock('shared/helpers/mitt', () => ({ emitter: copilotMocks.emitter }));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/helpers/MessageFormatter.js', () => ({
  default: class {
    constructor(content) {
      this.formattedMessage = content;
    }
  },
}));

describe('CopilotAssistantMessage', () => {
  const wrappers = [];
  const mountAssistant = (props = {}) => {
    const wrapper = mount(CopilotAssistantMessage, {
      props: {
        message: { content: 'A **formatted** response' },
        ...props,
      },
      global: {
        mocks: { $t: key => key },
        directives: {
          'dompurify-html': (element, binding) => {
            element.innerHTML = binding.value;
          },
        },
        stubs: {
          Button: {
            template:
              '<button v-bind="$attrs" @click="$emit(\'click\')">{{ label }}<span :data-icon="icon" /></button>',
            props: ['icon', 'label'],
            emits: ['click'],
          },
        },
      },
      attachTo: document.body,
    });
    wrappers.push(wrapper);
    return wrapper;
  };

  beforeEach(() => {
    clipboard.copy.mockResolvedValue(undefined);
    clipboard.copy.mockClear();
    copilotMocks.emitter.emit.mockClear();
    useAlert.mockClear();
    useTrack.mockClear();
  });

  afterEach(() => {
    wrappers.forEach(wrapper => wrapper.unmount());
    wrappers.length = 0;
    vi.useRealTimers();
  });

  it('identifies Copilot, copies the response, and announces success', async () => {
    const wrapper = mountAssistant();
    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.COPILOT_LABEL');

    const copyButton = wrapper.get(
      'button[aria-label="CAPTAIN.COPILOT.COPY_RESPONSE"]'
    );
    expect(copyButton.attributes('title')).toBe(
      'CAPTAIN.COPILOT.COPY_RESPONSE'
    );
    await copyButton.trigger('click');

    expect(clipboard.copy).toHaveBeenCalledWith('A **formatted** response');
    expect(useAlert).toHaveBeenCalledWith('CAPTAIN.COPILOT.COPIED');
    expect(wrapper.get('[role="status"]').text()).toBe(
      'CAPTAIN.COPILOT.COPIED'
    );
    expect(copyButton.get('[data-icon]').attributes('data-icon')).toBe(
      'i-lucide-check'
    );
  });

  it('returns to the copy icon after 1.5 seconds and reports clipboard errors', async () => {
    vi.useFakeTimers();
    const wrapper = mountAssistant();
    const copyButton = wrapper.get('button');
    await copyButton.trigger('click');
    await vi.advanceTimersByTimeAsync(1500);

    expect(copyButton.get('[data-icon]').attributes('data-icon')).toBe(
      'i-lucide-copy'
    );

    clipboard.copy.mockRejectedValueOnce(new Error('clipboard unavailable'));
    await copyButton.trigger('click');
    expect(useAlert).toHaveBeenCalledWith('CAPTAIN.COPILOT.COPY_ERROR');
  });

  it('uses a response only for the latest suggested reply and tracks the action', async () => {
    const wrapper = mountAssistant({
      isLastMessage: true,
      message: { content: 'A **formatted** response', reply_suggestion: true },
      timeLabel: '2 minutes ago',
    });

    expect(wrapper.text()).toContain('2 minutes ago');
    expect(wrapper.findAll('button')).toHaveLength(2);
    const useButton = wrapper.get(
      'button[aria-label="CAPTAIN.COPILOT.USE_RESPONSE"]'
    );
    expect(useButton.attributes('title')).toBe('CAPTAIN.COPILOT.USE_RESPONSE');
    await useButton.trigger('click');

    expect(emitter.emit).toHaveBeenCalledWith(
      BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
      'A **formatted** response'
    );
    expect(useTrack).toHaveBeenCalledWith(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
  });

  it('keeps the action row space and reveals actions on hover, focus, and touch', () => {
    const wrapper = mountAssistant({
      message: { content: 'A response', reply_suggestion: true },
      timeLabel: 'Now',
    });
    const actions = wrapper.get('.min-h-8');

    expect(wrapper.classes()).toContain('group');
    expect(actions.classes()).toContain('opacity-0');
    expect(actions.classes()).toContain('group-hover:opacity-100');
    expect(actions.classes()).toContain('group-focus-within:opacity-100');
    expect(actions.classes()).toContain('[@media(hover:none)]:opacity-100');
    expect(actions.classes()).toContain('motion-reduce:transition-none');

    const copyButton = wrapper.get('button');
    copyButton.element.focus();
    expect(copyButton.element.matches(':focus')).toBe(true);
  });

  it('hides the use action except for a nonempty latest suggested reply', () => {
    const earlier = mountAssistant({
      message: { content: 'A response', reply_suggestion: true },
      isLastMessage: false,
    });
    const notSuggested = mountAssistant({
      message: { content: 'A response' },
      isLastMessage: true,
    });
    const empty = mountAssistant({
      message: { content: '', reply_suggestion: true },
      isLastMessage: true,
    });

    expect(earlier.findAll('button')).toHaveLength(1);
    expect(notSuggested.findAll('button')).toHaveLength(1);
    expect(empty.findAll('button')).toHaveLength(0);
  });

  it('renders failed responses with a retry action', async () => {
    const wrapper = mountAssistant({
      isLastMessage: true,
      message: { content: 'Could not respond', error: true },
    });

    expect(wrapper.vm.messageContent).toBe('Could not respond');
    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.RETRY');
    expect(wrapper.classes()).toContain('text-n-ruby-11');
    await wrapper.findAll('button').at(0).trigger('click');
    expect(wrapper.emitted('retry')).toHaveLength(1);
  });
});
