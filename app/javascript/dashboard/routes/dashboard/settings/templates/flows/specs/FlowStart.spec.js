import { mount } from '@vue/test-utils';
import FlowStart from '../FlowStart.vue';

const mountStart = () =>
  mount(FlowStart, { global: { mocks: { $t: key => key } } });

describe('FlowStart', () => {
  it('offers "En blanco" first and continues with "Continuar"', async () => {
    const wrapper = mountStart();

    expect(
      wrapper
        .findAll('[data-testid^="flow-starting-"]')[0]
        .attributes('data-testid')
    ).toBe('flow-starting-blank');
    expect(wrapper.get('[data-testid="flow-start-create"]').text()).toBe(
      'WHATSAPP_FLOWS.START.CONTINUE'
    );

    await wrapper
      .get('[data-testid="flow-start-name"] input')
      .setValue('Mi flow');
    await wrapper.get('[data-testid="flow-start-create"]').trigger('click');

    const [started] = wrapper.emitted('create')[0];
    expect(started.name).toBe('Mi flow');
    expect(started.definition.screens[0].title).toBe('Pantalla 1');
  });

  it('shows the name as an error only when it is empty after trying to continue', async () => {
    const wrapper = mountStart();
    const input = () => wrapper.get('[data-testid="flow-start-name"] input');

    expect(input().classes()).not.toContain('error');
    await input().setValue('Mi flow');
    expect(input().classes()).not.toContain('error');

    await input().setValue('');
    await wrapper.get('[data-testid="flow-start-create"]').trigger('click');
    expect(input().classes()).toContain('error');
    expect(wrapper.emitted('create')).toBeUndefined();
  });
});
