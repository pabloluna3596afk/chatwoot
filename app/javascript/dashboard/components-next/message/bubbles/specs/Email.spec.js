import { defineComponent, ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { useResizeObserver } from '@vueuse/core';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import Email from '../Email/Index.vue';
import { provideMessageContext } from '../../provider';

vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useResizeObserver: vi.fn(),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: ref({ locale: 'en' }) }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: ref({ locale: 'en' }) }),
}));

const render = (html = '<p>Seven new notifications</p>', messageType = 0) => {
  const Host = defineComponent({
    components: { Email },
    setup() {
      provideMessageContext({
        id: ref(1),
        content: ref('Seven new notifications'),
        contentAttributes: ref({ email: { htmlContent: { full: html } } }),
        attachments: ref([]),
        messageType: ref(messageType),
        variant: ref('email'),
        orientation: ref(messageType === 0 ? 'left' : 'right'),
        shouldGroupWithNext: ref(false),
        inReplyTo: ref(null),
        sender: ref({ name: 'Ana', email: 'ana@example.com' }),
        status: ref('sent'),
      });
    },
    template: '<Email />',
  });
  return mount(Host, {
    global: {
      plugins: [VueDOMPurifyHTML],
      stubs: { MessageMeta: true },
    },
  });
};

describe('email expansion', () => {
  it.each([0, 1])(
    'expands incoming/outgoing HTML (%s) without covering the content',
    async messageType => {
      const wrapper = render(
        '<table><tr><td>Seven new notifications</td></tr></table>',
        messageType
      );
      const content = wrapper.get('[data-email-content]');
      Object.defineProperty(content.element, 'scrollHeight', {
        configurable: true,
        value: 850,
      });
      useResizeObserver.mock.calls[0][1]();
      await nextTick();
      const expand = wrapper.get('button[aria-expanded="false"]');
      expect(content.element.contains(expand.element)).toBe(false);
      expect(expand.element.previousElementSibling).toBe(
        content.element.parentElement
      );
      expect(content.element.parentElement.classList).toContain(
        'max-h-[25rem]'
      );
      expect(content.element.parentElement.classList).toContain(
        'overflow-hidden'
      );
      expect(wrapper.get('td').text()).toBe('Seven new notifications');
      await expand.trigger('click');
      expect(content.element.parentElement.classList).not.toContain(
        'max-h-[25rem]'
      );
      expect(content.element.parentElement.classList).toContain(
        'overflow-x-auto'
      );
      const collapse = wrapper.get('button[aria-expanded="true"]');
      expect(collapse.text()).toContain('EMAIL_HEADER.COLLAPSE');
      expect(collapse.classes()).toContain('min-h-10');
      expect(collapse.classes()).toContain('border-solid');
      expect(collapse.classes()).toContain('focus-visible:ring-2');
      await collapse.trigger('click');
      expect(content.element.parentElement.classList).toContain(
        'max-h-[25rem]'
      );
      expect(wrapper.get('button[aria-expanded="false"]').text()).toContain(
        'EMAIL_HEADER.EXPAND'
      );
      wrapper.unmount();
    }
  );

  it('does not offer expansion for a short email, including a resize back below the threshold', async () => {
    const wrapper = render();
    expect(wrapper.find('button[aria-expanded]').exists()).toBe(false);
    const content = wrapper.get('[data-email-content]');
    Object.defineProperty(content.element, 'scrollHeight', {
      configurable: true,
      value: 401,
    });
    const measure = useResizeObserver.mock.calls[0][1];
    measure();
    await nextTick();
    expect(wrapper.find('button[aria-expanded]').exists()).toBe(true);
    Object.defineProperty(content.element, 'scrollHeight', { value: 400 });
    measure();
    await nextTick();
    expect(wrapper.find('button[aria-expanded]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('toggles actual sanitized nested quotes without losing the message', async () => {
    const wrapper = render(
      '<p>Current email</p><blockquote><p>First quote</p><blockquote>Nested quote</blockquote></blockquote>'
    );
    expect(wrapper.text()).toContain('Current email');
    expect(wrapper.text()).not.toContain('Nested quote');
    const toggle = wrapper
      .findAll('button')
      .find(button => button.text().includes('SHOW_QUOTED_TEXT'));
    await toggle.trigger('click');
    expect(wrapper.text()).toContain('First quote');
    expect(wrapper.text()).toContain('Nested quote');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('HIDE_QUOTED_TEXT'))
      .trigger('click');
    expect(wrapper.text()).not.toContain('Nested quote');
    wrapper.unmount();
  });
});
