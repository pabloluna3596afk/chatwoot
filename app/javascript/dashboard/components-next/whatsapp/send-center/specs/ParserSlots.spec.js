import { h } from 'vue';
import { createI18n } from 'vue-i18n';
import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppTemplateParser from '../../WhatsAppTemplateParser.vue';
import ContentTemplateParser from 'dashboard/components-next/content-templates/ContentTemplateParser.vue';
import TemplateVariableInput from 'dashboard/components-next/variable/TemplateVariableInput.vue';
import EditableBody from '../EditableBody.vue';
import es from 'dashboard/i18n/locale/es/whatsappTemplates.json';

vi.mock('dashboard/components-next/variable-picker/VariablePicker.vue', () => ({
  default: { template: '<span />' },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: () => ({ provider: '360dialog' }) }),
}));
vi.mock('dashboard/api/variables', () => ({
  default: { catalog: vi.fn(async () => ({ data: { variables: [] } })) },
}));

describe('inline parser contract', () => {
  it('numbers repeated fields in reading order while sharing the same value', async () => {
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
    const inputs = wrapper.findAll('input');
    expect(inputs.map(input => input.attributes('aria-label'))).toEqual([
      'Nombre del cliente, dato 1 de 3',
      'Fecha, dato 2 de 3',
      'Nombre del cliente, dato 3 de 3',
    ]);
    expect(inputs.map(input => input.element.value)).toEqual([
      'Ana',
      '',
      'Ana',
    ]);
    expect(wrapper.findAll('input[autofocus]')).toHaveLength(1);
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
      const inputs = inline.findAll('[data-testid="editable-body"] input');
      expect(inputs).toHaveLength(6);
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
    const inputs = inline.findAll('input');
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
      attachTo: document.body,
      props: {
        text: 'Hello {{name}}, {{date}}',
        values: {},
        labelFor: key => key,
      },
    });
    await flushPromises();
    const inputs = wrapper.findAll('input');
    expect(document.activeElement).toBe(inputs[0].element);
    await inputs[0].trigger('compositionstart');
    inputs[0].element.value = 'に';
    await inputs[0].trigger('input');
    expect(wrapper.emitted('change')).toBeUndefined();
    inputs[0].element.value = '日本';
    await inputs[0].trigger('compositionend');
    expect(wrapper.emitted('change')).toEqual([['name', '日本']]);
    expect(inputs.map(input => input.attributes('placeholder'))).toEqual([
      'name',
      'date',
    ]);
    expect(inputs.every(input => !input.attributes('tabindex'))).toBe(true);
    wrapper.unmount();
  });
});
