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
      this.$emit('close');
    },
  },
  template:
    '<div v-if="visible" role="dialog"><h2>{{ title }}</h2><slot /><slot name="footer" /></div>',
};
const CheckboxStub = {
  props: ['modelValue', 'disabled', 'ariaLabel'],
  emits: ['update:modelValue'],
  template:
    '<input type="checkbox" :checked="modelValue" :disabled="disabled" :aria-label="ariaLabel" @change="$emit(\'update:modelValue\', $event.target.checked)" />',
};
const ComboBoxStub = {
  props: ['modelValue', 'options', 'id'],
  emits: ['update:modelValue'],
  template:
    '<select :id="id" :value="modelValue" @change="$emit(\'update:modelValue\', $event.target.value)"><option v-for="option in options" :key="option.value" :value="option.value">{{ option.label }}</option></select>',
};
const ButtonStub = {
  props: ['label', 'disabled', 'isLoading'],
  template:
    '<button type="button" :disabled="disabled" :data-testid="$attrs[\'data-testid\']">{{ label }}</button>',
};
const templates = [
  { key: 'confirmation', title: 'Confirmation', draftExists: true },
  { key: 'cancellation', title: 'Cancellation', draftExists: true },
  { key: 'reminder', title: 'Reminder', draftExists: true },
];
const accounts = [
  {
    waba_id: 'one',
    name: 'Sales',
    number: '+100',
    templates: {
      confirmation: { state: 'approved' },
      cancellation: { state: 'approved' },
      reminder: { state: 'approved' },
    },
  },
  {
    waba_id: 'two',
    name: 'Support',
    number: '+200',
    templates: {
      confirmation: { state: 'unsent' },
      cancellation: { state: 'failed' },
      reminder: { state: 'approved' },
    },
  },
  {
    waba_id: 'three',
    name: 'Clinic',
    number: '+300',
    templates: {
      confirmation: { state: 'approved' },
      cancellation: { state: 'review' },
      reminder: { state: 'rejected', reason: 'Invalid category' },
    },
  },
];
const singleAccount = {
  ...accounts[0],
  templates: {
    confirmation: { state: 'approved' },
    cancellation: { state: 'rejected', reason: 'Too long' },
    reminder: { state: 'review' },
  },
};
const fiveAccounts = [
  ...accounts,
  ...['four', 'five'].map((waba_id, index) => ({
    ...accounts[index],
    waba_id,
    name: `Inbox ${index + 4}`,
  })),
];
const render = props =>
  mount(TemplateSubmissionDialog, {
    props: { accounts: [accounts[0]], templates, ...props },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en, es } }),
      ],
      stubs: {
        Dialog: DialogStub,
        Checkbox: CheckboxStub,
        ComboBox: ComboBoxStub,
        Button: ButtonStub,
      },
    },
  });

describe('TemplateSubmissionDialog', () => {
  it('shows the three statuses without an account picker for one account', async () => {
    const wrapper = render({ accounts: [singleAccount] });
    await wrapper.vm.open();
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(3);
    expect(wrapper.findAll('input:disabled')).toHaveLength(2);
    expect(wrapper.text()).toContain('Rejected: "Too long"');
  });

  it('chooses the first pending account and sends a single account id', async () => {
    const wrapper = render({ accounts });
    await wrapper.vm.open();
    expect(wrapper.get('select').element.value).toBe('two');
    await wrapper.get('[data-testid="submit-templates"]').trigger('click');
    expect(wrapper.emitted('submit')[0][0]).toEqual({
      functions: ['confirmation', 'cancellation'],
      waba_ids: ['two'],
    });
  });

  it('supports three accounts and starts with the first one that has pending templates', async () => {
    const wrapper = render({ accounts });
    await wrapper.vm.open();

    expect(wrapper.findAll('select option')).toHaveLength(3);
    expect(wrapper.get('select').element.value).toBe('two');
    await wrapper.get('select').setValue('three');
    expect(wrapper.text()).toContain('Rejected: "Invalid category"');
    await wrapper.get('[data-testid="submit-templates"]').trigger('click');

    expect(wrapper.emitted('submit')[0][0]).toEqual({
      functions: ['reminder'],
      waba_ids: ['three'],
    });
  });

  it('shows five account options without changing the first pending selection', async () => {
    const wrapper = render({ accounts: fiveAccounts });
    await wrapper.vm.open();

    expect(wrapper.findAll('select option')).toHaveLength(5);
    expect(wrapper.get('select').element.value).toBe('two');
  });

  it('disables templates without a draft and disables submit when nothing is pending', async () => {
    const wrapper = render({
      templates: templates.map(template => ({
        ...template,
        draftExists: false,
      })),
    });
    await wrapper.vm.open();
    expect(wrapper.findAll('input:disabled')).toHaveLength(3);
    expect(wrapper.text()).toContain(
      'This account has no templates to submit.'
    );
    expect(
      wrapper.get('[data-testid="submit-templates"]').attributes('disabled')
    ).toBeDefined();
  });
});
