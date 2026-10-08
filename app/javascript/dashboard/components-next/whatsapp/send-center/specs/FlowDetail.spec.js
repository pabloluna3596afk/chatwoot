import { mount, flushPromises } from '@vue/test-utils';
import FlowDetail from '../FlowDetail.vue';
import { PHONE_PREVIEW_WIDTH } from '../../phonePreview';
import FlowPhoneFrame from 'dashboard/routes/dashboard/settings/templates/flows/FlowPhoneFrame.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => (key.endsWith('OPEN_FLOW') ? 'Open Flow' : key),
  }),
}));

describe('Flow message customization', () => {
  it('starts collapsed, updates its live preview and resets when choosing another Flow', async () => {
    const wrapper = mount(FlowDetail, {
      props: { flow: { id: 12, name: 'Appointment' } },
    });
    expect(wrapper.find('[data-testid="flow-send-body"]').exists()).toBe(false);
    expect(wrapper.vm.isValid).toBe(true);
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await wrapper
      .get('[data-testid="flow-send-header"] input')
      .setValue('Your appointment');
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('Choose a time');
    await wrapper.get('[data-testid="flow-send-cta"] input').setValue('Choose');
    expect(wrapper.get('[data-testid="send-center-preview"]').text()).toContain(
      'Choose a time'
    );
    expect(wrapper.vm.payload).toEqual({
      whatsapp_flow_id: 12,
      header: 'Your appointment',
      body: 'Choose a time',
      cta: 'Choose',
    });
    await wrapper.setProps({ flow: { id: 13, name: 'Contact details' } });
    expect(wrapper.vm.payload.body).toBe('Contact details');
    expect(wrapper.vm.payload.header).toBe('');
    expect(wrapper.find('[data-testid="flow-send-body"]').exists()).toBe(false);
  });
  it('opens customization beside the preview within two independently scrolling columns', async () => {
    const wrapper = mount(FlowDetail, {
      props: { flow: { id: 12, name: 'Appointment' } },
    });
    const columns = wrapper.get('[data-testid="flow-send-columns"]');
    expect(columns.classes()).toContain(
      'grid-cols-[var(--phone-preview-width)]'
    );
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(columns.classes()).toContain(
      'xl:grid-cols-[var(--phone-preview-width)_var(--send-center-unit)]'
    );
    const preview = wrapper.get('[data-testid="flow-send-preview-column"]');
    const fields = wrapper.get('[data-testid="flow-send-fields-column"]');
    expect(preview.element.parentElement).toBe(columns.element);
    expect(fields.element.parentElement).toBe(columns.element);
    expect(preview.classes()).toContain('overflow-y-auto');
    expect(preview.classes()).not.toContain('max-xl:hidden');
    expect(wrapper.vm.customizing).toBe(true);
    expect(fields.classes()).toContain('overflow-y-auto');
    expect(wrapper.find('[data-testid="flow-send-customize"]').exists()).toBe(
      false
    );
    expect(fields.get('[data-testid="flow-send-panel-header"]').element).toBe(
      fields.element.firstElementChild
    );
    expect(
      fields.get('[data-testid="flow-send-close-customize"]').exists()
    ).toBe(true);
  });

  it.each([
    [1440, false],
    [1440, true],
    [900, true],
  ])(
    'keeps the shared 360px preview track at viewport %i with customization %s',
    async (viewport, expanded) => {
      vi.stubGlobal('innerWidth', viewport);
      const wrapper = mount(FlowDetail, {
        props: { flow: { id: 12, name: 'Appointment' } },
      });
      if (expanded)
        await wrapper
          .get('[data-testid="flow-send-customize"]')
          .trigger('click');
      const columns = wrapper.get('[data-testid="flow-send-columns"]');
      expect(columns.classes()).toContain(
        'grid-cols-[var(--phone-preview-width)]'
      );
      expect(
        columns
          .classes()
          .filter(c => c.includes('grid-cols') && c.includes('xl:'))
      ).toEqual(
        expanded
          ? [
              'xl:grid-cols-[var(--phone-preview-width)_var(--send-center-unit)]',
            ]
          : []
      );
      expect(
        wrapper.get('[data-testid="flow-send-preview-column"]').classes()
      ).not.toContain('max-xl:hidden');
      const simulator = mount(FlowPhoneFrame, {
        props: { title: 'Appointment', screenIndex: 0, screenCount: 1 },
      });
      PHONE_PREVIEW_WIDTH.split(' ').forEach(token =>
        expect(simulator.classes()).toContain(token)
      );
      expect(PHONE_PREVIEW_WIDTH).toContain('[--phone-preview-width:22.5rem]');
      expect(simulator.classes()).toContain('w-[var(--phone-preview-width)]');
      simulator.unmount();
      wrapper.unmount();
      vi.unstubAllGlobals();
    }
  );

  it('keeps the closed customization button directly after the bubble without caption or field labels', () => {
    const wrapper = mount(FlowDetail, {
      props: { flow: { id: 12, name: 'Appointment' } },
    });
    const preview = wrapper.get('[data-testid="flow-send-preview-column"]');
    const button = wrapper.get('[data-testid="flow-send-customize"]');
    expect(button.element.parentElement).toBe(preview.element);
    expect(
      button.element.previousElementSibling.contains(
        wrapper.get('[data-testid="send-center-preview"]').element
      )
    ).toBe(true);
    expect(preview.text()).not.toContain('SEND_CENTER.PREVIEW');
    expect(preview.text()).not.toContain('SEND_CENTER.BODY');
    expect(
      wrapper.find('[data-testid="flow-send-modified-dot"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('focuses the first field, closes only the panel with Esc, and returns focus', async () => {
    const wrapper = mount(FlowDetail, {
      attachTo: document.body,
      props: { flow: { id: 12, name: 'Appointment' } },
    });
    const bubbled = vi.fn();
    document.body.addEventListener('keydown', bubbled);
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await flushPromises();
    const first = wrapper.get('[data-testid="flow-send-header"] input');
    expect(document.activeElement).toBe(first.element);
    await first.trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="flow-send-fields-column"]').exists()
    ).toBe(false);
    expect(bubbled).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(
      wrapper.get('[data-testid="flow-send-customize"]').element
    );
    document.body.removeEventListener('keydown', bubbled);
    wrapper.unmount();
  });

  it('retains edits while closed, indicates customization, restores defaults and resets on selection', async () => {
    const wrapper = mount(FlowDetail, {
      props: { flow: { id: 12, name: 'Appointment' } },
    });
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(
      wrapper.get('[data-testid="flow-send-restore"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .get('[data-testid="flow-send-header"] input')
      .setValue('Hello');
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('Choose a time');
    await wrapper.get('[data-testid="flow-send-cta"] input').setValue('Choose');
    expect(
      wrapper.get('[data-testid="flow-send-restore"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper
      .get('[data-testid="flow-send-close-customize"]')
      .trigger('click');
    expect(wrapper.get('[data-testid="flow-send-customize"]').text()).toBe(
      'WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZE'
    );
    expect(
      wrapper
        .get('[data-testid="flow-send-modified-dot"]')
        .attributes('aria-label')
    ).toBe('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZED_MESSAGE');
    expect(
      wrapper.get('[data-testid="flow-send-modified-dot"]').attributes('title')
    ).toBe('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZED_MESSAGE');
    expect(wrapper.get('[data-testid="send-center-preview"]').text()).toContain(
      'Choose a time'
    );
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(
      wrapper.get('[data-testid="flow-send-header"] input').element.value
    ).toBe('Hello');
    expect(
      wrapper.get('[data-testid="flow-send-body"] textarea').element.value
    ).toBe('Choose a time');
    await wrapper.get('[data-testid="flow-send-restore"]').trigger('click');
    expect(wrapper.vm.payload).toEqual({
      whatsapp_flow_id: 12,
      header: '',
      body: 'Appointment',
      cta: 'Open Flow',
    });
    expect(
      wrapper.get('[data-testid="flow-send-restore"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('Again');
    await wrapper.setProps({ flow: { id: 13, name: 'Contact' } });
    expect(wrapper.vm.payload.body).toBe('Contact');
    expect(
      wrapper.get('[data-testid="flow-send-customize"]').text()
    ).not.toContain('CUSTOMIZED');
    wrapper.unmount();
  });

  it('enforces the existing body/button limits and rejects emoji without changing the send contract', async () => {
    const wrapper = mount(FlowDetail, {
      props: { flow: { id: 12, name: 'Appointment' } },
    });
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await wrapper.get('[data-testid="flow-send-body"] textarea').setValue(' ');
    expect(wrapper.vm.isValid).toBe(false);
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('x'.repeat(1025));
    expect(wrapper.vm.isValid).toBe(false);
    await wrapper
      .get('[data-testid="flow-send-body"] textarea')
      .setValue('Choose a time');
    await wrapper
      .get('[data-testid="flow-send-cta"] input')
      .setValue('x'.repeat(21));
    expect(wrapper.vm.isValid).toBe(false);
    await wrapper
      .get('[data-testid="flow-send-cta"] input')
      .setValue('Open 😀');
    expect(wrapper.vm.isValid).toBe(false);
    expect(wrapper.vm.invalidReason).toContain('button_no_emoji');
    await wrapper.get('[data-testid="flow-send-cta"] input').setValue('Open');
    expect(wrapper.vm.isValid).toBe(true);
  });
});
