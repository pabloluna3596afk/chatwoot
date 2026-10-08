import { mount } from '@vue/test-utils';
import FlowDetail from '../FlowDetail.vue';

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
    expect(columns.classes()).toContain('grid-cols-1');
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(columns.classes()).toContain('grid-cols-2');
    const preview = wrapper.get('[data-testid="flow-send-preview-column"]');
    const fields = wrapper.get('[data-testid="flow-send-fields-column"]');
    expect(preview.element.parentElement).toBe(columns.element);
    expect(fields.element.parentElement).toBe(columns.element);
    expect(preview.classes()).toContain('overflow-y-auto');
    expect(fields.classes()).toContain('overflow-y-auto');
    expect(
      wrapper
        .get('[data-testid="flow-send-customize"]')
        .attributes('aria-expanded')
    ).toBe('true');
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
    expect(wrapper.get('[role="alert"]').text()).toContain('button_no_emoji');
    await wrapper.get('[data-testid="flow-send-cta"] input').setValue('Open');
    expect(wrapper.vm.isValid).toBe(true);
  });
});
