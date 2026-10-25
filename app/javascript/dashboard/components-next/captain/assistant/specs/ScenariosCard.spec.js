import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { nextTick, ref } from 'vue';
import ScenariosCard from '../ScenariosCard.vue';

vi.mock('@vueuse/core', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    useElementSize: () => ({ height: ref(240), width: ref(400) }),
  };
});

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      CAPTAIN: {
        ASSISTANTS: {
          SCENARIOS: {
            SHOW_MORE: 'Show more',
            SHOW_LESS: 'Show less',
            SELECT_SCENARIO: 'Select scenario: {title}',
            EDIT_SCENARIO: 'Edit scenario: {title}',
            DELETE_SCENARIO: 'Delete scenario: {title}',
            STATUS: {
              ENABLED: 'Enabled',
              DISABLED: 'Disabled',
              TOGGLE: '{title}',
            },
            UPDATE: { CANCEL: 'Cancel', UPDATE: 'Save' },
            ADD: {
              SUGGESTED: { TOOLS_USED: 'Tools used' },
              NEW: {
                FORM: {
                  TITLE: {
                    LABEL: 'Title',
                    PLACEHOLDER: 'Title',
                    ERROR: 'Required',
                  },
                  DESCRIPTION: {
                    LABEL: 'Description',
                    PLACEHOLDER: 'Description',
                    ERROR: 'Required',
                  },
                  INSTRUCTION: {
                    LABEL: 'Instruction',
                    PLACEHOLDER: 'Instruction',
                    ERROR: 'Required',
                  },
                },
              },
            },
          },
        },
      },
    },
  },
});

const stubs = {
  Input: {
    props: ['label', 'modelValue', 'disabled'],
    template:
      '<input :aria-label="label" :value="modelValue" :disabled="disabled" />',
  },
  TextArea: {
    props: ['label', 'modelValue', 'disabled'],
    template:
      '<textarea :aria-label="label" :value="modelValue" :disabled="disabled" />',
  },
  Editor: {
    props: ['label', 'modelValue', 'disabled'],
    template:
      '<div contenteditable="true" tabindex="0" :aria-label="label">{{ modelValue }}</div>',
  },
  Policy: { template: '<div><slot /></div>' },
  Switch: { template: '<button type="button" />' },
};

const mountCard = () =>
  mount(ScenariosCard, {
    props: {
      id: 7,
      title: 'Refunds',
      description: 'Refund requests',
      instruction: 'Long instruction '.repeat(30),
      selectable: true,
      onUpdate: async () => true,
    },
    global: { plugins: [i18n], stubs },
  });

describe('ScenariosCard keyboard access', () => {
  it('expands and collapses the instruction with the labeled button', async () => {
    const wrapper = mountCard();
    const expand = wrapper.get(
      'button[aria-controls="scenario-instruction-7"]'
    );

    expect(expand.text()).toBe('Show more');
    expect(expand.attributes('aria-expanded')).toBe('false');
    expect(expand.attributes('type')).toBe('button');
    await expand.trigger('keydown', { key: 'Enter' });
    await expand.trigger('click');
    expect(expand.attributes('aria-expanded')).toBe('true');
    expect(expand.text()).toBe('Show less');

    await expand.trigger('keydown', { key: ' ' });
    await expand.trigger('click');
    expect(expand.attributes('aria-expanded')).toBe('false');
  });

  it('keeps selection and edit actions named and closes editing on Escape', async () => {
    const wrapper = mountCard();
    expect(wrapper.get('input[type="checkbox"]').attributes('aria-label')).toBe(
      'Select scenario: Refunds'
    );
    expect(
      wrapper.get('button[aria-label="Edit scenario: Refunds"]').exists()
    ).toBe(true);
    expect(
      wrapper.get('button[aria-label="Delete scenario: Refunds"]').exists()
    ).toBe(true);

    await wrapper
      .get('button[aria-label="Edit scenario: Refunds"]')
      .trigger('click');
    expect(wrapper.find('input[aria-label="Title"]').exists()).toBe(true);
    const escape = new KeyboardEvent('keydown', {
      key: 'Escape',
      bubbles: true,
      cancelable: true,
    });
    wrapper.get('input[aria-label="Title"]').element.dispatchEvent(escape);
    await nextTick();
    expect(escape.defaultPrevented).toBe(true);
    expect(wrapper.find('input[aria-label="Title"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Refunds');
  });
});
