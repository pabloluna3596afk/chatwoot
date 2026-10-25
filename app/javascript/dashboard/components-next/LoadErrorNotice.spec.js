import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LoadErrorNotice from './LoadErrorNotice.vue';

describe('LoadErrorNotice', () => {
  it('localizes its default retry label', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: {
        en: { COMPONENTS: { LOAD_ERROR_NOTICE: { RETRY: 'Try again' } } },
      },
    });
    const wrapper = mount(LoadErrorNotice, {
      props: { title: 'Could not load' },
      global: { plugins: [i18n], stubs: { Icon: true } },
    });

    expect(wrapper.get('button').text()).toBe('Try again');
    wrapper.unmount();
  });
});
