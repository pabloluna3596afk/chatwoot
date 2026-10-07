import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import FlowPhoneSimulator from '../FlowPhoneSimulator.vue';
import FlowPhoneCanvas from '../FlowPhoneCanvas.vue';
import FlowPreviewResult from '../FlowPreviewResult.vue';
import FlowPreviewMessage from '../FlowPreviewMessage.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import esFlow from 'dashboard/i18n/locale/es/whatsappFlows.json';
import esConversation from 'dashboard/i18n/locale/es/conversation.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('FlowPhoneSimulator', () => {
  let wrapper;
  let definition;
  let global;
  let requests;
  beforeEach(() => {
    definition = {
      screens: [
        {
          title: 'Tus datos',
          button: 'Continuar',
          blocks: [
            {
              type: 'short_text',
              key: 'name',
              label: 'Nombre',
              required: true,
              save_to: { target: 'contact.name' },
            },
            {
              type: 'dropdown',
              key: 'topic',
              label: 'Motivo',
              options: [
                { id: 'general', title: 'General' },
                { id: 'other', title: 'Otro' },
              ],
            },
            {
              type: 'short_text',
              key: 'detail',
              label: 'Detalle',
              required: true,
              visible_when: { key: 'topic', op: 'equals', value: 'other' },
            },
          ],
        },
        {
          title: 'Confirmación',
          button: 'Enviar',
          blocks: [
            { type: 'optin', key: 'consent', label: 'Acepto', required: true },
            { type: 'long_text', key: 'optional', label: 'Opcional' },
          ],
        },
      ],
    };
    global = {
      plugins: [
        createStore({ getters: { getSelectedChatAttachments: () => [] } }),
        createI18n({
          legacy: false,
          locale: 'es',
          messages: { es: { ...esFlow, ...esConversation } },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      directives: {
        dompurifyHtml: (el, binding) => {
          el.textContent = binding.value;
        },
      },
    };
    requests = vi
      .spyOn(window, 'fetch')
      .mockRejectedValue(new Error('No network in preview'));
    wrapper = mount(FlowPhoneSimulator, {
      attachTo: document.body,
      props: { definition, flowName: 'Contacto' },
      global,
    });
  });
  afterEach(() => {
    wrapper.unmount();
    requests.mockRestore();
  });

  it('validates required fields only on submit and focuses the first error', async () => {
    expect(wrapper.text()).not.toContain('Completa este campo');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.text()).toContain('Completa este campo para continuar');
    expect(wrapper.get('#flow-preview-name').attributes('aria-invalid')).toBe(
      'true'
    );
    expect(document.activeElement).toBe(
      wrapper.get('#flow-preview-name').element
    );
    expect(wrapper.get('[data-testid="flow-phone-frame"]').text()).toContain(
      '1 / 2'
    );
  });

  it('reacts to visibility changes and discards hidden answers permanently', async () => {
    await wrapper.get('#flow-preview-name').setValue('Ana');
    wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', 'other');
    await flushPromises();
    await wrapper.get('#flow-preview-detail').setValue('Viejo');
    wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', 'general');
    await flushPromises();
    expect(wrapper.find('#flow-preview-detail').exists()).toBe(false);
    wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', 'other');
    await flushPromises();
    expect(wrapper.get('#flow-preview-detail').element.value).toBe('');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.text()).toContain('Completa este campo');
  });

  it('navigates screens, renders the real answer card and sent bubble, omits empties, and makes no requests', async () => {
    const before = JSON.stringify(definition);
    await wrapper.get('#flow-preview-name').setValue('Ana');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.get('[data-testid="flow-phone-frame"]').text()).toContain(
      '2 / 2'
    );
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    const sentBubble = wrapper.find('[data-bubble-name="whatsapp-flow-sent"]');
    expect(sentBubble.exists()).toBe(true);
    expect(sentBubble.find('.font-semibold').exists()).toBe(false);
    expect(sentBubble.find('.font-medium').text()).toContain('Contacto');
    expect(sentBubble.find('.prose-bubble').text()).toMatch(
      /^(<p>)?Contacto(<\/p>)?$/
    );
    expect(
      wrapper.find('[data-bubble-name="whatsapp-flow-response"]').exists()
    ).toBe(true);
    expect(wrapper.findAll('dt').map(item => item.text())).toEqual([
      'Nombre',
      'Acepto',
    ]);
    expect(wrapper.findAll('dd').map(item => item.text())).toEqual([
      'Ana',
      'Sí',
    ]);
    expect(wrapper.find('[data-testid="flow-response-copy"]').exists()).toBe(
      true
    );
    await wrapper
      .get('[data-testid="flow-preview-destinations-toggle"]')
      .trigger('click');
    expect(wrapper.get('#flow-preview-destinations').text()).toContain(
      'Nombre → Nombre'
    );
    expect(JSON.stringify(definition)).toBe(before);
    expect(requests).not.toHaveBeenCalled();
  });

  it('keeps the same fixed phone frame as Editar and contains scrolling inside it', () => {
    const canvas = mount(FlowPhoneCanvas, {
      props: { definition, screenIndex: 0 },
      global,
    });
    const edit = canvas.get('[data-testid="flow-phone-frame"]');
    const trying = wrapper.get('[data-testid="flow-phone-frame"]');
    expect(trying.attributes('class')).toBe(edit.attributes('class'));
    expect(trying.classes()).toContain('w-[22.5rem]');
    expect(trying.classes()).toContain('h-[46.25rem]');
    expect(
      wrapper.get('[data-testid="flow-phone-scroll"]').classes()
    ).toContain('overflow-y-auto');
    canvas.unmount();
  });

  it('resets responses and navigation, and offers returning to Editar after completion', async () => {
    await wrapper.get('#flow-preview-name').setValue('Ana');
    await wrapper.get('form').trigger('submit');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    await wrapper.get('[data-testid="flow-result-edit"]').trigger('click');
    expect(wrapper.emitted('edit')).toHaveLength(1);
    await wrapper.get('[data-testid="flow-result-reset"]').trigger('click');
    expect(wrapper.get('#flow-preview-name').element.value).toBe('');
    expect(wrapper.findComponent(FlowPreviewResult).exists()).toBe(false);
  });

  it('uses app controls for number/date/text, choices and simulated files', async () => {
    const types = [
      'short_text',
      'date',
      'long_text',
      'radio',
      'checkbox',
      'photo',
      'document',
    ];
    await wrapper.setProps({
      definition: {
        screens: [
          {
            title: 'Tipos',
            button: 'Enviar',
            blocks: types.map(type => ({
              type,
              key: type,
              label: type,
              input: 'number',
              options: [{ id: 'a', title: 'A' }],
              max_files: 2,
            })),
          },
        ],
      },
    });
    expect(wrapper.findAllComponents(Input)).toHaveLength(2);
    expect(wrapper.find('input[type="date"]').exists()).toBe(true);
    expect(wrapper.find('input[type="radio"]').exists()).toBe(true);
    expect(wrapper.findComponent(Checkbox).exists()).toBe(true);
    expect(wrapper.find('input[type="file"]').exists()).toBe(false);
    wrapper.findComponent(RadioCard).vm.$emit('select', 'flow-preview-radio-a');
    await flushPromises();
    expect(wrapper.get('input[type="radio"]').element.checked).toBe(true);
    await wrapper.get('[data-field="photo"] button').trigger('click');
    expect(wrapper.get('[data-field="photo"]').text()).toContain(
      'Archivo de prueba'
    );
  });

  it('passes the original field keys and metadata into reused message components', async () => {
    await wrapper.get('#flow-preview-name').setValue('Ana');
    await wrapper.get('form').trigger('submit');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    const response = wrapper
      .findAllComponents(FlowPreviewMessage)
      .find(item => item.props('kind') === 'response');
    expect(response.props('answers')).toEqual({ name: 'Ana', consent: true });
    expect(response.props('flowName')).toBe('Contacto');
  });
});
