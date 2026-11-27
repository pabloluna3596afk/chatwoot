import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import TemplatePreviewDrawer from '../TemplatePreviewDrawer.vue';
import activationEn from 'dashboard/i18n/locale/en/calendarActivationKit.json';

const SidePanelStub = {
  props: ['title', 'description'],
  emits: ['close'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
    return {};
  },
  template:
    '<section><button data-testid="close" @click="$emit(\'close\')"></button><slot /></section>',
};

describe('TemplatePreviewDrawer', () => {
  it('shows a rejected reason and restores focus when the panel closes', async () => {
    const wrapper = mount(TemplatePreviewDrawer, {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: activationEn },
          }),
        ],
        stubs: {
          SidePanel: SidePanelStub,
          WhatsAppBubble: true,
          Button: {
            props: ['label'],
            template:
              '<button data-testid="correct" @click="$emit(\'click\')">{{ label }}</button>',
          },
        },
      },
    });
    const trigger = { focus: vi.fn() };
    await wrapper.vm.open(trigger, {
      title: 'Cancellation',
      state: 'rejected',
      statusLabel: 'Rejected',
      color: 'ruby',
      reason: 'Too long',
      preview: { body: 'See you soon', buttons: [] },
      language: 'en',
      draftId: 42,
    });

    expect(wrapper.text()).toContain(
      'Meta\'s reason: "Too long". Fix the text and submit it again.'
    );
    await wrapper.get('[data-testid="correct"]').trigger('click');
    expect(wrapper.emitted('correct')[0]).toEqual([42]);
    await wrapper.get('[data-testid="close"]').trigger('click');
    expect(trigger.focus).toHaveBeenCalledWith({ preventScroll: true });
  });
});
