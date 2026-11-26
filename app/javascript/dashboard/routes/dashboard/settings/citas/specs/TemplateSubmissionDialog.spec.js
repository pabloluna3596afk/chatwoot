import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import TemplateSubmissionDialog from '../TemplateSubmissionDialog.vue';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';

const DialogStub = {
  props: ['title', 'description', 'disableConfirmButton'],
  data: () => ({ visible: false }),
  methods: {
    open() {
      this.visible = true;
    },
    close() {
      this.visible = false;
    },
  },
  template:
    '<div v-if="visible"><h2>{{ title }}</h2><slot /><slot name="footer" /></div>',
};

const accounts = [
  { waba_id: 'one', channels: [{ id: 1, name: 'Sales' }] },
  { waba_id: 'two', channels: [{ id: 2, name: 'Support' }] },
];
const templates = [
  {
    key: 'confirmation',
    title: 'Confirmation',
    description: 'Sent when booked.',
  },
  {
    key: 'cancellation',
    title: 'Cancellation',
    description: 'Sent when cancelled.',
  },
  {
    key: 'reminder',
    title: 'Reminder',
    description: 'Sent before the appointment.',
    disabled: true,
  },
];
const render = (locale = 'en') =>
  mount(TemplateSubmissionDialog, {
    props: { accounts, templates },
    global: {
      plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
      stubs: { Dialog: DialogStub },
    },
  });
const keyPaths = (value, prefix = '') =>
  Object.entries(value)
    .flatMap(([key, nested]) => {
      const path = prefix ? `${prefix}.${key}` : key;
      return [
        path,
        ...(nested && typeof nested === 'object' ? keyPaths(nested, path) : []),
      ];
    })
    .sort();

describe('TemplateSubmissionDialog', () => {
  it('keeps English and Spanish submission copy in key parity', () => {
    expect(keyPaths(en.CALENDAR_TEMPLATES.SUBMISSION)).toEqual(
      keyPaths(es.CALENDAR_TEMPLATES.SUBMISSION)
    );
  });

  it.each([
    [
      'en',
      'Send 2 templates to 1 account. No messages will be sent to customers.',
    ],
    [
      'es',
      'Se enviarán 2 plantillas a 1 cuenta. No se manda ningún mensaje a clientes.',
    ],
  ])(
    'shows the selected summary and prevents empty submission in %s',
    async (locale, expected) => {
      const wrapper = render(locale);
      await wrapper.vm.open();
      expect(wrapper.text()).toContain(expected);
      const send = wrapper
        .findAll('button')
        .find(
          button =>
            button.text() ===
            (locale === 'en' ? 'Send for approval' : 'Enviar a aprobación')
        );
      expect(send.attributes('disabled')).toBeUndefined();
      const accountInputs = wrapper
        .findAll('input[type="checkbox"]')
        .slice(0, 2);
      await accountInputs[0].setValue(false);
      expect(wrapper.text()).toContain(
        locale === 'en'
          ? 'Select at least one account'
          : 'Elige al menos una cuenta'
      );
      expect(send.attributes('disabled')).not.toBeUndefined();
    }
  );

  it('emits selected templates and accounts while leaving rejected and failed templates retryable', async () => {
    const retryableTemplates = templates.map((template, index) => ({
      ...template,
      disabled: index === 2,
    }));
    const wrapper = mount(TemplateSubmissionDialog, {
      props: { accounts, templates: retryableTemplates },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
        stubs: { Dialog: DialogStub },
      },
    });
    await wrapper.vm.open();
    const inputs = wrapper.findAll('input[type="checkbox"]');
    expect(inputs[2].attributes('disabled')).toBeUndefined();
    expect(inputs[3].attributes('disabled')).toBeUndefined();
    expect(inputs[4].attributes('disabled')).toBeDefined();
    await inputs[1].setValue(true);
    await inputs[3].setValue(false);
    await wrapper.findAll('button').at(-1).trigger('click');
    expect(wrapper.emitted('submit')[0][0]).toEqual({
      waba_ids: ['one', 'two'],
      functions: ['confirmation'],
    });
  });

  it.each([
    [
      'en',
      'Send 1 template to 2 accounts. No messages will be sent to customers.',
    ],
    [
      'es',
      'Se enviarán 1 plantilla a 2 cuentas. No se manda ningún mensaje a clientes.',
    ],
  ])(
    'pluralizes one template and multiple accounts in %s',
    async (locale, expected) => {
      const wrapper = render(locale);
      await wrapper.vm.open();
      const inputs = wrapper.findAll('input[type="checkbox"]');
      await inputs[1].setValue(true);
      await inputs[3].setValue(false);
      expect(wrapper.text()).toContain(expected);
    }
  );
});
