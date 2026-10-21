import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import VariableDeliveryWarning from './VariableDeliveryWarning.vue';
import en from 'dashboard/i18n/locale/en/variables.json';
import es from 'dashboard/i18n/locale/es/variables.json';

const render = (diagnostic, locale = 'en') =>
  mount(VariableDeliveryWarning, {
    props: { diagnostic },
    global: {
      plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
    },
  });

describe('Captain variable delivery diagnosis', () => {
  it('hides the warning when no delivery has failed', () => {
    expect(render(null).find('[role="status"]').exists()).toBe(false);
  });

  it.each(['en', 'es'])(
    'localizes the persisted reason in %s without exposing Liquid or customer values',
    locale => {
      const wrapper = render(
        {
          template: 'reminder',
          path: 'body.1',
          status: 'missing',
          at: '2026-10-20T00:00:00Z',
        },
        locale
      );
      expect(wrapper.get('[role="status"]').text()).toContain('reminder');
      expect(wrapper.text()).toContain('body.1');
      expect(wrapper.text()).not.toContain('{{');
      expect(wrapper.text()).not.toContain('VARIABLES.');
      expect(wrapper.text()).toContain(
        locale === 'es' ? 'Falta un valor' : 'Missing value'
      );
    }
  );
});
