import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AppointmentReminderReadiness from './AppointmentReminderReadiness.vue';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';

const english = en.CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS;
const spanish = es.CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS;

describe('Appointment reminder preparation', () => {
  it('keeps English and neutral Spanish keys in parity', () => {
    expect(Object.keys(spanish)).toEqual(Object.keys(english));
    expect(Object.keys(spanish.STATUS)).toEqual(Object.keys(english.STATUS));
    expect(JSON.stringify(spanish)).not.toMatch(
      /[\u3400-\u9fff]|\b(vos|tenés|podés|activá|guardá)\b/u
    );
    expect(JSON.stringify(spanish)).not.toContain('?');
  });

  it.each(['en', 'es'])('explains every inbox status in %s', locale => {
    const inboxes = Object.keys(english.STATUS).map((status, index) => ({
      inbox_id: index,
      inbox_name: `Inbox ${index}`,
      status,
      missing: status === 'template_changed' ? ['body.2', 'header.media'] : [],
    }));
    const wrapper = mount(AppointmentReminderReadiness, {
      props: { inboxes },
      global: {
        stubs: { RouterLink: { template: '<a><slot /></a>' } },
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
      },
    });
    const copy = locale === 'es' ? spanish : english;
    inboxes.forEach(inbox => {
      expect(
        wrapper
          .get(`[data-testid="reminder-readiness-${inbox.inbox_id}"]`)
          .text()
      ).toContain(copy.STATUS[inbox.status]);
    });
    expect(wrapper.text()).toContain(copy.SAVED_HELP);
    expect(wrapper.text()).toContain(copy.DELIVERY_HELP);
    expect(wrapper.text()).toContain('body.2, header.media');
    expect(wrapper.text()).not.toContain('READINESS.');
  });
});
