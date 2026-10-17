import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/login.json';
import es from 'dashboard/i18n/locale/es/login.json';
import Input from './Input.vue';

describe('FormInput', () => {
  let wrapper;

  afterEach(() => wrapper?.unmount());

  it.each([
    [false, 'en'],
    [true, 'en'],
    [false, 'es'],
    [true, 'es'],
  ])(
    'toggles the real password button with outlined=%s in %s',
    async (outlined, locale) => {
      const messages = { en, es }[locale].LOGIN.PASSWORD;
      wrapper = mount(Input, {
        props: {
          label: 'Password',
          name: 'password',
          type: 'password',
          modelValue: 'secret',
          outlined,
        },
        global: {
          plugins: [
            createI18n({ legacy: false, locale, messages: { en, es } }),
          ],
          stubs: { Button: false, NextButton: false },
        },
      });
      const input = wrapper.get('input');
      const button = wrapper.get('button[type="button"]');

      expect(input.attributes('type')).toBe('password');
      expect(button.attributes('aria-pressed')).toBe('false');
      expect(button.find('.i-lucide-eye').exists()).toBe(true);
      await button.trigger('click');
      expect(input.attributes('type')).toBe('text');
      expect(button.attributes('aria-pressed')).toBe('true');
      expect(button.attributes('aria-label')).toBe(messages.HIDE);
      expect(button.find('.i-lucide-eye-off').exists()).toBe(true);
      await button.trigger('click');
      expect(input.attributes('type')).toBe('password');
      expect(button.attributes('aria-pressed')).toBe('false');
      expect(button.attributes('aria-label')).toBe(messages.SHOW);
      expect(input.element.value).toBe('secret');
    }
  );
});
