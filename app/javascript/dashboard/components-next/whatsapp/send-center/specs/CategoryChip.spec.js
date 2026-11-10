import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CategoryChip from '../CategoryChip.vue';
import en from 'dashboard/i18n/locale/en/whatsappTemplates.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplates.json';

describe('template category chips', () => {
  it.each([
    ['en', 'MARKETING', 'amber'],
    ['es', 'MARKETING', 'amber'],
    ['en', 'UTILITY', 'teal'],
    ['es', 'UTILITY', 'teal'],
    ['en', 'AUTHENTICATION', 'iris'],
    ['es', 'AUTHENTICATION', 'iris'],
  ])(
    'shares category names with the filter in %s for %s',
    async (locale, category, color) => {
      const wrapper = mount(CategoryChip, {
        props: { category },
        global: {
          plugins: [
            createI18n({ legacy: false, locale, messages: { en, es } }),
          ],
        },
      });
      const source = { en, es }[locale].WHATSAPP_TEMPLATES.SEND_CENTER;
      expect(wrapper.text()).toBe(source.CATEGORY[category]);
      expect(wrapper.attributes('title')).toBe(source.CATEGORY_HELP[category]);
      expect(wrapper.classes()).toContain(`bg-n-${color}-3`);
      expect(wrapper.classes()).toContain(`text-n-${color}-11`);
      await wrapper.setProps({ category: 'UNKNOWN' });
      expect(wrapper.find('span').exists()).toBe(false);
      await wrapper.setProps({ category: '' });
      expect(wrapper.find('span').exists()).toBe(false);
      wrapper.unmount();
    }
  );
});
