import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import FloatingVue from 'floating-vue';
import en from 'dashboard/i18n/locale/en';
import es from 'dashboard/i18n/locale/es';
import FlowHeader from '../FlowHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

describe.each(['en', 'es'])('FlowHeader in %s', locale => {
  const messages = { en, es };
  const plugins = config.global.plugins;
  let wrapper;

  afterEach(() => {
    wrapper?.unmount();
    config.global.plugins = plugins;
  });

  it('renders its domain from the effective catalog and preserves editing actions', async () => {
    const i18n = createI18n({
      legacy: false,
      locale,
      fallbackLocale: false,
      messages,
    });
    config.global.plugins = [i18n, FloatingVue];
    wrapper = mount(FlowHeader, {
      props: {
        name: 'Mi recorrido / Customer path',
        description: 'Texto propio / Custom content',
        category: 'Ventas / Sales',
      },
      global: { stubs: { NextButton: false, NextInput: false } },
    });

    expect(wrapper.get('[role="group"]').attributes('aria-label')).toBe(
      i18n.global.t('FLOWS.HEADER')
    );
    expect(wrapper.text()).not.toContain('FLOWS.');
    const inputs = wrapper.findAllComponents(Input);
    expect(inputs.map(input => input.props('modelValue'))).toEqual([
      'Mi recorrido / Customer path',
      'Texto propio / Custom content',
      'Ventas / Sales',
    ]);
    await inputs[0].get('input').setValue('Nombre personalizado');
    expect(wrapper.emitted('update:name')).toEqual([['Nombre personalizado']]);

    const buttons = wrapper.findAllComponents(Button);
    expect(buttons[0].attributes('aria-label')).toBe(
      i18n.global.t('FLOWS.EDIT.OVERVIEW_TOOLTIP')
    );
    await buttons[0].trigger('click');
    await buttons[1].trigger('click');
    await buttons[2].trigger('click');
    expect(wrapper.emitted('open-overview')).toHaveLength(1);
    expect(wrapper.emitted('open-exit')).toHaveLength(1);
    expect(wrapper.emitted('submit')).toHaveLength(1);
    await wrapper.setProps({ saving: true });
    expect(wrapper.findAllComponents(Button)[2].props('isLoading')).toBe(true);
  });
});
