import { createI18n } from 'vue-i18n';
import en from './locale/en';
import es from './locale/es';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: false,
  messages: { en },
});

describe('appointment attribute labels', () => {
  it('keeps all six English and Spanish attributes in parity without CJK copy', () => {
    const english = en.CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES;
    const spanish = es.CALENDAR_APPOINTMENT_ATTRIBUTES.ATTRIBUTES;
    const keys = [
      'ultima_cita',
      'proxima_cita',
      'proxima_cita_titulo',
      'total_citas',
      'estado_proxima_cita',
      'citas_canceladas',
    ];
    expect(Object.keys(english)).toEqual(keys);
    expect(Object.keys(spanish)).toEqual(keys);
    keys.forEach(key => {
      expect(Object.keys(english[key])).toEqual(['NAME', 'HELP']);
      expect(Object.keys(spanish[key])).toEqual(['NAME', 'HELP']);
      expect(JSON.stringify([english[key], spanish[key]])).not.toMatch(
        /[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/
      );
    });
    expect(english.estado_proxima_cita.NAME).toBe('Next appointment status');
    expect(spanish.estado_proxima_cita.NAME).toBe('Estado de la próxima cita');
    expect(english.citas_canceladas.NAME).toBe('Cancelled appointments');
    expect(spanish.citas_canceladas.NAME).toBe('Citas canceladas');
  });
});

describe('operational glossary in the effective English catalog', () => {
  it.each([
    ['SIDEBAR.FLOWS', 'Conversation Flows'],
    ['FLOWS.HEADER', 'Conversation Flows'],
    ['FLOWS.ADD.FORM.NAME.LABEL', 'Conversation Flow name'],
    ['FLOWS.HEADER_BTN_TXT_SAVE', 'Save Conversation Flow'],
    ['AUTOMATION.ACTIONS.ENTER_FLOW', 'Start Conversation Flow'],
    ['WHATSAPP_FLOWS.TAB', 'WhatsApp Flows'],
    ['WHATSAPP_FLOWS.LIST.TITLE', 'WhatsApp Flows'],
    ['WHATSAPP_FLOWS.EDITOR.NAME', 'WhatsApp Flow name'],
    ['WHATSAPP_FLOWS.EDITOR.BACK_TO_LIST', 'Back to WhatsApp Flows'],
    ['WHATSAPP_FLOWS.SEND.TITLE', 'Send WhatsApp Flow'],
    ['CAPTAIN.ASSISTANTS.GUARDRAILS.TITLE', 'Safety limits'],
    ['CAPTAIN.PLAYGROUND.SETUP.GUARDRAILS.TAB_TITLE', 'Safety limits'],
    [
      'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.GUARDRAILS.TITLE',
      'Safety limits',
    ],
    ['PROFILE_SETTINGS.FORM.ACCESS_TOKEN.RESET', 'Regenerate token'],
  ])(
    'resolves %s without fallback and keeps a Spanish counterpart',
    (key, text) => {
      // The table deliberately exercises real lookup paths at runtime.
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      expect(i18n.global.t(key)).toBe(text);
      const spanish = createI18n({
        legacy: false,
        locale: 'es',
        fallbackLocale: false,
        messages: { es },
      });
      // The Spanish wording is reviewed through Crowdin, not authored in this PR.
      expect(spanish.global.te(key)).toBe(true);
    }
  );

  it('preserves plural counts and customer data in messages', () => {
    expect(i18n.global.t('FLOWS.COUNT', { n: 2 }, 2)).toBe(
      '2 Conversation Flows'
    );
    expect(
      i18n.global.t('WHATSAPP_FLOWS.META.TEST_SENT', { number: '+593999' })
    ).toBe('WhatsApp Flow sent to +593999.');
    expect(
      i18n.global.t(
        'ASSIGNMENT_POLICY.AGENT_ASSIGNMENT_POLICY.EDIT.CONFIRM_ADD_INBOX_DIALOG.DESCRIPTION',
        {
          inboxName: 'Mi bandeja / My inbox',
        }
      )
    ).toContain('Mi bandeja / My inbox');
  });
});
