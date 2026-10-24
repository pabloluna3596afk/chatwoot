import { mount, config } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import CalendarWeek from '../components/CalendarWeek.vue';
import { getWeeksForMonth } from '../helpers/DatePickerHelper';

it('uses the application locale for every day label and updates when it changes', async () => {
  const plugins = config.global.plugins;
  const i18n = createI18n({ legacy: false, locale: 'es', messages: {} });
  config.global.plugins = [i18n];
  const month = new Date(2026, 0, 1);
  const wrapper = mount(CalendarWeek, {
    props: {
      currentDate: month,
      startCurrentDate: month,
      endCurrentDate: new Date(2026, 1, 1),
    },
  });
  try {
    expect(
      wrapper
        .findAll('.grid > button')
        .map(button => button.attributes('aria-label'))
    ).toEqual(
      getWeeksForMonth(month)
        .flat()
        .map(day => day.toLocaleDateString('es', { dateStyle: 'full' }))
    );
    i18n.global.locale.value = 'en';
    await nextTick();
    expect(
      wrapper
        .findAll('.grid > button')
        .map(button => button.attributes('aria-label'))
    ).toEqual(
      getWeeksForMonth(month)
        .flat()
        .map(day => day.toLocaleDateString('en', { dateStyle: 'full' }))
    );
  } finally {
    wrapper.unmount();
    config.global.plugins = plugins;
  }
});
