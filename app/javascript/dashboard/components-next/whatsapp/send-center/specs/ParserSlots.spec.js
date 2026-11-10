import { h } from 'vue';
import { createI18n } from 'vue-i18n';
import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppTemplateParser from '../../WhatsAppTemplateParser.vue';
import ContentTemplateParser from 'dashboard/components-next/content-templates/ContentTemplateParser.vue';
import TemplateVariableInput from 'dashboard/components-next/variable/TemplateVariableInput.vue';
import VariablesAPI from 'dashboard/api/variables';
import TemplateDataField from '../TemplateDataField.vue';
import EditableBody from '../EditableBody.vue';
import ChatPreview from '../ChatPreview.vue';
import es from 'dashboard/i18n/locale/es/whatsappTemplates.json';

vi.mock('dashboard/components-next/variable-picker/VariablePicker.vue', () => ({
  default: { props: ['filter', 'surface'], template: '<span />' },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: () => ({ provider: '360dialog' }) }),
}));
vi.mock('dashboard/api/variables', () => ({
  default: {
    catalog: vi.fn(async () => ({ data: { variables: [] } })),
    preview: vi.fn(),
  },
}));

describe('inline parser contract', () => {
  it('replaces fallback inputs and preserves missing-contact hints and variable insertion', async () => {
    VariablesAPI.preview.mockImplementation(async payload => ({
      data: {
        results: [payload.texts.map(() => ({ value: '', status: 'missing' }))],
      },
    }));
    const wrapper = mount(WhatsAppTemplateParser, {
      props: {
        template: {
          name: 'contact',
          components: [{ type: 'BODY', text: 'Hi {{name}}' }],
        },
        defaultValues: { name: '{{ contact.name }}' },
        resolveContext: { contact: { id: 1 }, conversation: { id: 2 } },
      },
      slots: {
        preview: preview =>
          h(
            ChatPreview,
            {
              messages: [preview.bodyMessage('name')].filter(Boolean),
            },
            {
              default: () =>
                h(EditableBody, {
                  text: preview.bodyText,
                  values: preview.bodyValues,
                  labelFor: key => key,
                  variableFilter: preview.variableFilter,
                  onChange: preview.setBodyValue,
                  onSelect: preview.insertBodyVariable,
                }),
            }
          ),
        'body-fields': () => null,
      },
    });
    await flushPromises();
    expect(wrapper.findAll('textarea')).toHaveLength(1);
    expect(wrapper.findAllComponents(TemplateVariableInput)).toHaveLength(0);
    expect(wrapper.get('[data-testid=preview-help]').text()).toBe(
      'WHATSAPP_TEMPLATES.PARSER.NO_VALUE'
    );
    expect(wrapper.get('[data-testid=editable-body]').text()).not.toContain(
      'WHATSAPP_TEMPLATES.PARSER.NO_VALUE'
    );
    const picker = wrapper.findComponent(TemplateDataField);
    picker.vm.$emit('select', '{{ contact.email }}');
    await flushPromises();
    expect(wrapper.vm.processedParams.body.name).toBe(
      '{{ contact.name }} {{ contact.email }}'
    );
    await wrapper.get('textarea').setValue('Ana');
    await flushPromises();
    expect(wrapper.text()).not.toContain('WHATSAPP_TEMPLATES.PARSER.NO_VALUE');
    expect(wrapper.vm.isFormInvalid).toBe(false);
    wrapper.unmount();
  });

  it('uses the same data number and value for repeated variables', async () => {
    const wrapper = mount(EditableBody, {
      props: {
        text: '{{name}} / {{date}} / {{name}}',
        values: { name: 'Ana' },
        labelFor: key => (key === 'name' ? 'Nombre del cliente' : 'Fecha'),
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
        ],
      },
    });
    await flushPromises();
    const inputs = wrapper.findAll('textarea');
    expect(inputs.map(input => input.attributes('aria-label'))).toEqual([
      'Dato 1 de 2: Dato 1',
      'Dato 2 de 2: Dato 2',
      'Dato 1 de 2: Dato 1',
    ]);
    expect(inputs.map(input => input.element.value)).toEqual([
      'Ana',
      '',
      'Ana',
    ]);
    expect(wrapper.findAll('textarea')).toHaveLength(3);
    wrapper.unmount();
  });
  it.each([false, true])(
    'keeps WhatsApp payloads identical with rendered content %s',
    async sendRenderedContent => {
      const props = {
        sendRenderedContent,
        template: {
          name: 'appointment',
          category: 'UTILITY',
          language: 'es',
          components: [
            { type: 'HEADER', format: 'IMAGE' },
            {
              type: 'BODY',
              text: 'Hello {{1}}, {{2}} / {{3}} / {{4}} / {{5}} / {{6}}',
            },
            {
              type: 'BUTTONS',
              buttons: [
                {
                  type: 'URL',
                  text: 'Order',
                  url: 'https://example.com/{{1}}',
                },
              ],
            },
          ],
        },
        modelValue: {
          header: { media_url: 'https://example.com/image.jpg' },
          buttons: { 0: { type: 'url', parameter: '123' } },
        },
      };
      const classic = mount(WhatsAppTemplateParser, { props });
      const inline = mount(WhatsAppTemplateParser, {
        props,
        slots: {
          preview: preview =>
            h(EditableBody, {
              text: preview.bodyText,
              values: preview.bodyValues,
              labelFor: key => `Data ${key}`,
              onChange: preview.setBodyValue,
            }),
          'body-fields': () => null,
        },
      });
      await flushPromises();
      const values = ['Ana', '2026-11-09', '12:30', 'Six', 'Order', '{{2}}'];
      const inputs = inline.findAll('[data-testid="editable-body"] textarea');
      expect(inputs).toHaveLength(6);
      expect(inline.findAllComponents(TemplateVariableInput)).toHaveLength(0);
      expect(classic.findAllComponents(TemplateVariableInput)).toHaveLength(6);
      await Promise.all(
        values.map(async (value, index) => {
          classic
            .findAllComponents(TemplateVariableInput)
            [index].vm.$emit('update:modelValue', value);
          await inputs[index].setValue(value);
        })
      );
      await flushPromises();
      await classic
        .findAll('[data-template-fields] input')
        .at(-1)
        .setValue('123');
      await inline
        .findAll('[data-template-fields] input')
        .at(-1)
        .setValue('123');
      expect(inline.vm.isFormInvalid).toBe(false);
      classic.vm.sendMessage();
      inline.vm.sendMessage();
      expect(inline.emitted('sendMessage')).toEqual(
        classic.emitted('sendMessage')
      );
      expect(
        inline.emitted('sendMessage')[0][0].templateParams.processed_params.body
      ).toEqual(
        Object.fromEntries(values.map((value, index) => [index + 1, value]))
      );
      expect(
        inline.find('[data-template-fields] input[type=url]').exists()
      ).toBe(true);
      classic.unmount();
      inline.unmount();
    }
  );

  it('keeps Twilio Content payloads identical through its scoped preview', async () => {
    const props = {
      template: {
        friendly_name: 'hello',
        language: 'en',
        body: 'Hi {{1}}, order {{2}}',
      },
    };
    const classic = mount(ContentTemplateParser, { props });
    const inline = mount(ContentTemplateParser, {
      props,
      slots: {
        preview: preview =>
          h(EditableBody, {
            text: preview.bodyText,
            values: preview.bodyValues,
            labelFor: key => key,
            onChange: preview.setBodyValue,
          }),
        'body-fields': () => null,
      },
    });
    await flushPromises();
    classic
      .findAllComponents(TemplateVariableInput)[0]
      .vm.$emit('update:modelValue', 'Ana');
    classic
      .findAllComponents(TemplateVariableInput)[1]
      .vm.$emit('update:modelValue', '{{1}}');
    expect(inline.findAllComponents(TemplateVariableInput)).toHaveLength(0);
    expect(classic.findAllComponents(TemplateVariableInput)).toHaveLength(2);
    const inputs = inline.findAll('textarea');
    await inputs[0].setValue('Ana');
    await inputs[1].setValue('{{1}}');
    await flushPromises();
    classic.vm.sendMessage();
    inline.vm.sendMessage();
    expect(inline.emitted('sendMessage')).toEqual(
      classic.emitted('sendMessage')
    );
    expect(
      inline.emitted('sendMessage')[0][0].templateParams.processed_params
    ).toEqual({ 1: 'Ana', 2: '{{1}}' });
    classic.unmount();
    inline.unmount();
  });

  it('supports IME without committing partial composition and retains reading order', async () => {
    const wrapper = mount(EditableBody, {
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
        ],
      },
      attachTo: document.body,
      props: {
        text: 'Hello {{name}}, {{date}}',
        values: {},
        labelFor: key => key,
      },
    });
    await flushPromises();
    const inputs = wrapper.findAll('textarea');
    expect(document.activeElement).toBe(inputs[0].element);
    await inputs[0].trigger('compositionstart');
    inputs[0].element.value = 'に';
    await inputs[0].trigger('input');
    expect(wrapper.emitted('change')).toBeUndefined();
    inputs[0].element.value = '日本';
    await inputs[0].trigger('compositionend');
    expect(wrapper.emitted('change')).toEqual([['name', '日本']]);
    expect(inputs.map(input => input.attributes('placeholder'))).toEqual([
      'Dato 1',
      'Dato 2',
    ]);
    expect(inputs.every(input => !input.attributes('tabindex'))).toBe(true);
    wrapper.unmount();
  });
});

describe('formatted field payload parity', () => {
  it.each([false, true])(
    'preserves typed and selected values with rendered content %s',
    async sendRenderedContent => {
      VariablesAPI.preview.mockImplementation(async payload => ({
        data: {
          results: [
            payload.texts.map(() => ({ status: 'value', value: 'Alex Demo' })),
          ],
        },
      }));
      const props = {
        sendRenderedContent,
        resolveContext: { contact: { id: 1 } },
        template: {
          name: 'formatted',
          category: 'UTILITY',
          language: 'en',
          components: [{ type: 'BODY', text: '*Hello {{1}}*' }],
        },
      };
      const classic = mount(WhatsAppTemplateParser, { props });
      const inline = mount(WhatsAppTemplateParser, {
        props,
        slots: {
          preview: preview =>
            h(EditableBody, {
              text: preview.bodyText,
              values: preview.bodyValues,
              labelFor: key => key,
              onChange: preview.setBodyValue,
              onSelect: (key, expression) => {
                inline.vm.processedParams.body[key] = '';
                preview.insertBodyVariable(key, expression);
              },
            }),
        },
      });
      await flushPromises();
      const value = '*literal* <img onerror=x>';
      classic
        .getComponent(TemplateVariableInput)
        .vm.$emit('update:modelValue', value);
      inline.getComponent(TemplateDataField).vm.$emit('change', value);
      await flushPromises();
      classic.vm.sendMessage();
      inline.vm.sendMessage();
      expect(inline.emitted('sendMessage')).toEqual(
        classic.emitted('sendMessage')
      );
      expect(
        inline.emitted('sendMessage')[0][0].templateParams.processed_params
          .body['1']
      ).toBe(value);
      classic.unmount();
      inline.unmount();
      const selected = mount(WhatsAppTemplateParser, { props });
      const selectedInline = mount(WhatsAppTemplateParser, {
        props,
        slots: {
          preview: preview =>
            h(EditableBody, {
              text: preview.bodyText,
              values: preview.bodyValues,
              labelFor: key => key,
              onSelect: (key, expression) => {
                selectedInline.vm.processedParams.body[key] = '';
                preview.insertBodyVariable(key, expression);
              },
            }),
        },
      });
      await flushPromises();
      selected
        .getComponent(TemplateVariableInput)
        .vm.$emit('select', { expression: '{{ contact.name }}' });
      selectedInline
        .getComponent(TemplateDataField)
        .vm.$emit('select', '{{ contact.name }}');
      await flushPromises();
      selected.vm.sendMessage();
      selectedInline.vm.sendMessage();
      expect(selectedInline.emitted('sendMessage')).toEqual(
        selected.emitted('sendMessage')
      );
      expect(
        selectedInline.emitted('sendMessage')[0][0].pendingMessageContent
      ).toBe('*Hello Alex Demo*');
      selected.unmount();
      selectedInline.unmount();
    }
  );
});
