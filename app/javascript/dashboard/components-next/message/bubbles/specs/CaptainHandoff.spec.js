import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';
import CaptainHandoff from '../CaptainHandoff.vue';
import { provideMessageContext } from '../../provider.js';

const mountCard = ({
  category = 'tool_failure',
  summaryLines = [],
  locale = 'en',
  sender = { name: 'Luna' },
} = {}) => {
  const converted = useCamelCase(
    {
      content_attributes: {
        captain_handoff: { reason_category: category, source: 'tool' },
      },
    },
    { deep: true }
  );
  return mount(
    defineComponent({
      components: { CaptainHandoff },
      setup() {
        provideMessageContext({
          content: ref('Needs help\nWith a second line <script>'),
          sender: ref(sender),
          contentAttributes: ref(converted.contentAttributes),
        });
        return { summaryLines };
      },
      template: '<CaptainHandoff :summary-lines="summaryLines" />',
    }),
    {
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
        stubs: { BaseBubble: { template: '<div><slot /></div>' } },
      },
    }
  );
};

describe('CaptainHandoff', () => {
  it('keeps the note visible after its assistant is deleted', () => {
    expect(mountCard({ sender: null }).text()).toContain(
      'an assistant handed off this conversation'
    );
  });

  it.each([
    ['en', 'Luna handed off this conversation', 'Technical failure'],
    ['es', 'Luna pasó esta conversación', 'Fallo técnico'],
  ])('renders title and reason label in %s', (locale, title, label) => {
    const wrapper = mountCard({ locale });
    expect(wrapper.text()).toContain(title);
    expect(wrapper.text()).toContain(label);
  });

  it.each(['unrecognized', null, ''])(
    'falls back to the unclassified label for %s',
    category => {
      expect(mountCard({ category }).text()).toContain('Unclassified');
    }
  );

  it('renders the note content', () => {
    const wrapper = mountCard();
    expect(wrapper.get('p').text()).toBe(
      'Needs help\nWith a second line <script>'
    );
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.get('p').classes()).toContain('whitespace-pre-wrap');
    expect(wrapper.find('ul').exists()).toBe(false);
  });

  it('renders summary lines when provided', () => {
    const wrapper = mountCard({
      summaryLines: ['First', 'Second', 'Third', 'Fourth'],
    });
    expect(wrapper.findAll('li').map(line => line.text())).toEqual([
      'First',
      'Second',
      'Third',
    ]);
  });
});
