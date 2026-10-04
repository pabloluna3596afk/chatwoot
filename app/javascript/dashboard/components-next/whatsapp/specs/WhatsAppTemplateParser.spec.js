import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';

import WhatsAppTemplateParser from '../WhatsAppTemplateParser.vue';
import InsertVariableButton from 'dashboard/components-next/variable/InsertVariableButton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const { inboxState, uploadTemplateMedia } = vi.hoisted(() => ({
  inboxState: { provider: 'whatsapp_cloud' },
  uploadTemplateMedia: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: () => inboxState }),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: { uploadTemplateMedia },
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

  it('fills a named variable in by its name when nothing was saved, and keeps what was saved', async () => {
    const defaultValues = {
      nombre: '{{ contact.name }}',
      fecha: '{{ appointment.date }}',
    };

    const fresh = mountParser({ defaultValues });
    await nextTick();
    expect(fresh.vm.processedParams.body.nombre).toBe('{{ contact.name }}');
    expect(fresh.vm.processedParams.body.fecha).toBe('{{ appointment.date }}');
    expect(fresh.vm.processedParams.header.titulo).toBe('');

    const saved = mountParser({
      defaultValues,
      modelValue: { body: { nombre: 'Ana', fecha: '' }, header: {} },
    });
    await nextTick();
    expect(saved.vm.processedParams.body.nombre).toBe('Ana');
    expect(saved.vm.processedParams.body.fecha).toBe('');
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

describe('WhatsAppTemplateParser with a media header', () => {
  const mediaTemplate = {
    name: 'promo',
    category: 'MARKETING',
    language: 'es',
    components: [
      { type: 'HEADER', format: 'IMAGE', example: { header_handle: ['x'] } },
      { type: 'BODY', text: 'Hola' },
    ],
  };
  const uploaded = {
    media_id: '555',
    media_blob: 'signed',
    media_url: 'https://example.com/promo.png',
    media_name: 'promo.png',
    media_type: 'image',
    media_uploaded_at: '2030-01-01T00:00:00Z',
    media_phone_number_id: '123',
  };
  const mountMedia = (props = {}) =>
    shallowMount(WhatsAppTemplateParser, {
      props: { template: mediaTemplate, ...props },
      global: { mocks: { $t: key => key } },
    });
  const file = (type, size = 1024) => {
    const f = new File(['x'], 'promo', { type });
    Object.defineProperty(f, 'size', { value: size });
    return f;
  };

  beforeEach(() => {
    uploadTemplateMedia.mockReset();
    inboxState.provider = 'whatsapp_cloud';
  });

  it('offers the upload only for a WhatsApp Cloud inbox', () => {
    expect(mountMedia().vm.canUploadMedia).toBe(false);
    expect(mountMedia({ mediaInboxId: 7 }).vm.canUploadMedia).toBe(true);

    inboxState.provider = 'default';
    expect(mountMedia({ mediaInboxId: 7 }).vm.canUploadMedia).toBe(false);
  });

  it('keeps the uploaded file in the header params and sends them', async () => {
    uploadTemplateMedia.mockResolvedValue({ data: uploaded });
    const wrapper = mountMedia({ mediaInboxId: 7 });

    await wrapper.vm.uploadMedia(file('image/png'));

    expect(uploadTemplateMedia).toHaveBeenCalledWith(7, {
      format: 'IMAGE',
      file: expect.any(File),
    });
    expect(wrapper.vm.processedParams.header).toMatchObject(uploaded);

    wrapper.vm.sendMessage();
    expect(
      wrapper.emitted('sendMessage')[0][0].templateParams.processed_params
        .header
    ).toMatchObject({ media_id: '555', media_blob: 'signed' });
  });

  it('refuses a file the header does not accept without calling the API', async () => {
    const wrapper = mountMedia({ mediaInboxId: 7 });

    await wrapper.vm.uploadMedia(file('application/pdf'));
    expect(wrapper.vm.mediaError).toBe(
      'WHATSAPP_TEMPLATES.PARSER.MEDIA_ERROR_INVALID_TYPE'
    );

    await wrapper.vm.uploadMedia(file('image/png', 6 * 1024 * 1024));
    expect(wrapper.vm.mediaError).toBe(
      'WHATSAPP_TEMPLATES.PARSER.MEDIA_ERROR_TOO_LARGE'
    );
    expect(uploadTemplateMedia).not.toHaveBeenCalled();
  });

  it('shows the upload error when Meta or the server refuses the file', async () => {
    uploadTemplateMedia.mockRejectedValue({
      response: { data: { error: 'upload_failed' } },
    });
    const wrapper = mountMedia({ mediaInboxId: 7 });

    await wrapper.vm.uploadMedia(file('image/png'));

    expect(wrapper.vm.mediaError).toBe(
      'WHATSAPP_TEMPLATES.PARSER.MEDIA_ERROR_UPLOAD_FAILED'
    );
    expect(wrapper.vm.processedParams.header.media_id).toBeUndefined();
  });

  it('drops the uploaded file when a link is typed or the file is removed', async () => {
    uploadTemplateMedia.mockResolvedValue({ data: uploaded });
    const wrapper = mountMedia({ mediaInboxId: 7 });
    await wrapper.vm.uploadMedia(file('image/png'));

    wrapper.vm.updateMediaUrl('https://example.com/other.png');
    expect(wrapper.vm.processedParams.header).toMatchObject({
      media_url: 'https://example.com/other.png',
    });
    expect(wrapper.vm.processedParams.header.media_id).toBeUndefined();

    await wrapper.vm.uploadMedia(file('image/png'));
    wrapper.vm.removeUploadedMedia();
    expect(wrapper.vm.processedParams.header.media_id).toBeUndefined();
    expect(wrapper.vm.processedParams.header.media_url).toBe('');
  });

  it('restores the uploaded file of a saved value', () => {
    const wrapper = mountMedia({
      mediaInboxId: 7,
      modelValue: { header: { ...uploaded } },
    });

    expect(wrapper.vm.processedParams.header).toMatchObject({
      media_id: '555',
      media_blob: 'signed',
    });
  });
});
