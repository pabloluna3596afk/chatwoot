import { mount } from '@vue/test-utils';
import Input from './Input.vue';

describe('FormInput', () => {
  let wrapper;

  afterEach(() => wrapper?.unmount());

  it.each([false, true])(
    'toggles the real password button with outlined=%s',
    async outlined => {
      wrapper = mount(Input, {
        props: {
          label: 'Password',
          name: 'password',
          type: 'password',
          modelValue: 'secret',
          outlined,
        },
        global: { stubs: { Button: false, NextButton: false } },
      });
      const input = wrapper.get('input');
      const button = wrapper.get('button[type="button"]');

      expect(input.attributes('type')).toBe('password');
      expect(button.attributes('aria-pressed')).toBe('false');
      expect(button.find('.i-lucide-eye').exists()).toBe(true);
      await button.trigger('click');
      expect(input.attributes('type')).toBe('text');
      expect(button.attributes('aria-pressed')).toBe('true');
      expect(button.attributes('aria-label')).toBe('Hide password');
      expect(button.find('.i-lucide-eye-off').exists()).toBe(true);
      await button.trigger('click');
      expect(input.attributes('type')).toBe('password');
      expect(button.attributes('aria-pressed')).toBe('false');
      expect(button.attributes('aria-label')).toBe('Show password');
      expect(input.element.value).toBe('secret');
    }
  );
});
