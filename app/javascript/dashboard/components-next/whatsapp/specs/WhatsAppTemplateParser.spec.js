import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';

import WhatsAppTemplateParser from '../WhatsAppTemplateParser.vue';
import InsertVariableButton from 'dashboard/components-next/variable/InsertVariableButton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const template = {
  name: 'token_values',
  category: 'UTILITY',
  language: 'en',
  parameter_format: 'POSITIONAL',
  components: [
    {
      type: 'BODY',
      text: '{{1}} / {{2}}',
      example: {
        body_text: [['First', 'Second']],
      },
    },
  ],
};

describe('WhatsAppTemplateParser', () => {
  let wrapper;

  beforeEach(async () => {
    wrapper = shallowMount(WhatsAppTemplateParser, {
      props: { template },
      global: {
        mocks: {
          $t: key => key,
        },
      },
    });

    wrapper.vm.processedParams.body['1'] = '{{2}}';
    wrapper.vm.processedParams.body['2'] = 'Bob';
    await nextTick();
  });

  it('sends the original template body instead of the rendered preview', () => {
    expect(wrapper.vm.renderedTemplate).toBe('{{2}} / Bob');

    wrapper.vm.sendMessage();

    expect(wrapper.emitted('sendMessage')[0][0]).toMatchObject({
      message: '{{1}} / {{2}}',
      pendingMessageContent: '{{2}} / Bob',
      templateParams: {
        content_mode: 'raw_template',
        processed_params: {
          body: {
            1: '{{2}}',
            2: 'Bob',
          },
        },
      },
    });
  });

  it('sends rendered content when requested for an API inbox template', async () => {
    await wrapper.setProps({ sendRenderedContent: true });

    wrapper.vm.sendMessage();

    expect(wrapper.emitted('sendMessage')[0][0]).toMatchObject({
      message: '{{2}} / Bob',
      pendingMessageContent: '{{2}} / Bob',
      templateParams: {
        content_mode: 'rendered',
      },
    });
  });
});

describe('WhatsAppTemplateParser with the options of a Captain setting', () => {
  const named = {
    name: 'cita',
    category: 'UTILITY',
    language: 'es',
    parameter_format: 'NAMED',
    components: [
      { type: 'HEADER', format: 'TEXT', text: 'Cita {{titulo}}' },
      { type: 'BODY', text: 'Hola {{nombre}}, es el {{fecha}}.' },
    ],
  };
  const variableOptions = [
    { key: 'contact.name', label: 'Nombre del cliente' },
    { key: 'appointment.date', label: 'Fecha de la cita' },
  ];
  const previewValues = {
    'contact.name': 'Ana Pérez',
    'appointment.date': 'jueves 1 de octubre',
  };

  const mountParser = props =>
    shallowMount(WhatsAppTemplateParser, {
      props: { template: named, ...props },
      global: { mocks: { $t: key => key } },
    });

  it('shows no insert button when no variables are offered (the default)', () => {
    const wrapper = mountParser();

    expect(wrapper.findAllComponents(InsertVariableButton)).toHaveLength(0);
  });

  it('offers the variables next to every field of the header and the body', async () => {
    const wrapper = mountParser({ variableOptions });
    await nextTick();

    const buttons = wrapper.findAllComponents(InsertVariableButton);
    expect(buttons).toHaveLength(3);
    expect(buttons[0].props('variables')).toEqual(variableOptions);
  });

  it('inserts the variable as Liquid in the field it was chosen for', async () => {
    const wrapper = mountParser({ variableOptions });

    wrapper.vm.processedParams.body.nombre = 'Hola';
    await nextTick();
    const buttons = wrapper.findAllComponents(InsertVariableButton);
    buttons[1].vm.$emit('insert', '{{ contact.name }}');
    buttons[0].vm.$emit('insert', '{{ appointment.date }}');
    await nextTick();

    expect(wrapper.vm.processedParams.body.nombre).toBe(
      'Hola {{ contact.name }}'
    );
    expect(wrapper.vm.processedParams.header.titulo).toBe(
      '{{ appointment.date }}'
    );
  });

  it('previews sample values instead of the raw Liquid', async () => {
    const wrapper = mountParser({ variableOptions, previewValues });

    wrapper.vm.processedParams.header.titulo = 'de {{ contact.name }}';
    wrapper.vm.processedParams.body.nombre = '{{ contact.name }}';
    wrapper.vm.processedParams.body.fecha = '{{appointment.date}}';
    await nextTick();

    expect(wrapper.vm.renderedHeader).toBe('Cita de Ana Pérez');
    expect(wrapper.vm.renderedTemplate).toBe(
      'Hola Ana Pérez, es el jueves 1 de octubre.'
    );
  });

  it('keeps an expression it has no sample for', async () => {
    const wrapper = mountParser({ previewValues });

    wrapper.vm.processedParams.body.nombre = '{{ contact.other }}';
    await nextTick();

    expect(wrapper.vm.renderedTemplate).toContain('{{ contact.other }}');
  });

  it('starts from the values already chosen and reports every change', async () => {
    const wrapper = mountParser({
      modelValue: {
        body: { nombre: '{{ contact.name }}' },
        header: { titulo: 'Consulta' },
      },
    });
    await nextTick();

    expect(wrapper.vm.processedParams.body).toEqual({
      nombre: '{{ contact.name }}',
      fecha: '',
    });
    expect(wrapper.vm.processedParams.header).toEqual({ titulo: 'Consulta' });

    wrapper.vm.processedParams.body.fecha = '{{ appointment.date }}';
    await nextTick();

    const emitted = wrapper.emitted('update:modelValue');
    expect(emitted.at(-1)[0].body).toEqual({
      nombre: '{{ contact.name }}',
      fecha: '{{ appointment.date }}',
    });
  });

  it('does not report changes when it is not used with a value', async () => {
    const wrapper = mountParser();

    wrapper.vm.processedParams.body.nombre = 'x';
    await nextTick();

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
});
