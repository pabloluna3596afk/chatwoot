import {
  buildPayload,
  editRules,
  emptyForm,
  formFromTemplate,
  isEditable,
  newButton,
  previewTemplate,
  previewVariables,
  toSnakeCase,
  validateForm,
  variableNumbers,
  variableTokens,
  hasNamedVariables,
  isValidVariableName,
} from '../templateForm';

const validForm = () => {
  const form = emptyForm();
  form.inboxId = 3;
  form.name = 'recordatorio_cita';
  form.body.text = 'Tu cita queda confirmada.';
  return form;
};

describe('toSnakeCase', () => {
  it('turns a typed name into the name Meta accepts', () => {
    expect(toSnakeCase('Recordatorio de Cita')).toBe('recordatorio_de_cita');
    expect(toSnakeCase('  ¡Cancelación - hoy!  ')).toBe('cancelacion_hoy');
    expect(toSnakeCase('')).toBe('');
  });
});

describe('variableNumbers', () => {
  it('lists the variables in order without repeats', () => {
    expect(variableNumbers('{{1}} y {{2}} y {{1}}')).toEqual([1, 2]);
    expect(variableNumbers('sin variables')).toEqual([]);
  });
});

describe('validateForm', () => {
  it('accepts a minimal template', () => {
    expect(validateForm(validForm())).toEqual({});
  });

  it('asks for a channel and a valid name when creating, not when editing', () => {
    const form = validForm();
    form.inboxId = null;
    form.name = 'Con Espacio';

    expect(validateForm(form)).toMatchObject({
      inboxId: 'CHANNEL_REQUIRED',
      name: 'NAME_INVALID',
    });
    expect(validateForm(form, { isEdit: true })).toEqual({});
  });

  it('checks the body: required, length, order of variables, edges and examples', () => {
    const form = validForm();

    form.body.text = ' ';
    expect(validateForm(form)['body.text']).toBe('BODY_REQUIRED');
    form.body.text = 'a'.repeat(1025);
    expect(validateForm(form)['body.text']).toBe('BODY_TOO_LONG');
    form.body.text = 'Hola {{2}} adiós';
    expect(validateForm(form)['body.text']).toBe('VARIABLES_NOT_SEQUENTIAL');
    form.body.text = '{{1}} hola';
    expect(validateForm(form)['body.text']).toBe('VARIABLE_AT_EDGE');
    form.body.text = 'Hola {{1}}, adiós';
    form.body.examples = [''];
    expect(validateForm(form)['body.examples']).toBe('EXAMPLE_REQUIRED');
    form.body.examples = ['Ana'];
    expect(validateForm(form)).toEqual({});
  });

  it('checks the header', () => {
    const form = validForm();

    form.header.format = 'TEXT';
    expect(validateForm(form)['header.text']).toBe('HEADER_TEXT_REQUIRED');
    form.header.text = 'a'.repeat(61);
    expect(validateForm(form)['header.text']).toBe('HEADER_TEXT_TOO_LONG');
    form.header.text = '{{1}} {{2}}';
    expect(validateForm(form)['header.text']).toBe('HEADER_ONE_VARIABLE');
    form.header.text = 'Cita {{1}}';
    form.header.examples = [''];
    expect(validateForm(form)['header.example']).toBe('EXAMPLE_REQUIRED');
    form.header.format = 'IMAGE';
    expect(validateForm(form)['header.media']).toBe('HEADER_MEDIA_REQUIRED');
    form.header.handle = '4::handle';
    expect(validateForm(form)).toEqual({});
  });

  it('checks the footer and the buttons', () => {
    const form = validForm();

    form.footer.text = 'a'.repeat(61);
    expect(validateForm(form)['footer.text']).toBe('FOOTER_TOO_LONG');
    form.footer.text = 'Hola {{1}}';
    expect(validateForm(form)['footer.text']).toBe('FOOTER_NO_VARIABLES');
    form.footer.text = '';

    form.buttons = [
      newButton('QUICK_REPLY'),
      { ...newButton('URL'), text: 'Ver', url: 'ftp://x' },
      { ...newButton('PHONE_NUMBER'), text: 'Llamar', phoneNumber: '0999' },
    ];
    expect(validateForm(form)).toMatchObject({
      'buttons.0.text': 'BUTTON_TEXT_REQUIRED',
      'buttons.1.url': 'URL_INVALID',
      'buttons.2.phone': 'PHONE_INVALID',
    });
  });

  it('limits how many buttons there can be', () => {
    const form = validForm();
    form.buttons = Array.from({ length: 3 }, () => ({
      ...newButton('URL'),
      text: 'Ver',
      url: 'https://example.com',
    }));

    expect(validateForm(form).buttons).toBe('TOO_MANY_URL_BUTTONS');
  });
});

describe('buildPayload', () => {
  it('builds what the API takes, with only the examples that are needed', () => {
    const form = validForm();
    form.header.format = 'TEXT';
    form.header.text = 'Cita {{1}}';
    form.header.examples = ['lunes'];
    form.body.text = 'Hola {{1}}, tu cita es el {{2}}.';
    form.body.examples = ['Ana', 'lunes', 'sobra'];
    form.footer.text = 'Gracias';
    form.buttons = [
      { ...newButton('QUICK_REPLY'), text: 'Confirmar' },
      {
        ...newButton('URL'),
        text: 'Ver',
        url: 'https://example.com/c/{{1}}',
        examples: ['https://example.com/c/9'],
      },
      {
        ...newButton('PHONE_NUMBER'),
        text: 'Llamar',
        phoneNumber: '+593999999999',
      },
    ];

    expect(buildPayload(form)).toEqual({
      name: 'recordatorio_cita',
      language: 'es',
      category: 'UTILITY',
      header: {
        format: 'TEXT',
        text: 'Cita {{1}}',
        examples: ['lunes'],
        handle: '',
      },
      body: {
        text: 'Hola {{1}}, tu cita es el {{2}}.',
        examples: ['Ana', 'lunes'],
      },
      footer: { text: 'Gracias' },
      buttons: [
        { type: 'QUICK_REPLY', text: 'Confirmar' },
        {
          type: 'URL',
          text: 'Ver',
          url: 'https://example.com/c/{{1}}',
          examples: ['https://example.com/c/9'],
        },
        { type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '+593999999999' },
      ],
    });
  });
});

describe('preview', () => {
  it('shapes the form like a Meta template, with the examples as variable values', () => {
    const form = validForm();
    form.body.text = 'Hola {{1}}, tu cita es el {{2}}.';
    form.body.examples = ['Ana', 'lunes'];
    form.footer.text = 'Gracias';

    const template = previewTemplate(form);

    expect(template.components.map(component => component.type)).toEqual([
      'BODY',
      'FOOTER',
    ]);
    expect(previewVariables(form)).toEqual({ 1: 'Ana', 2: 'lunes' });
  });
});

describe('named variables', () => {
  it('reads the variables of a text, named or numbered', () => {
    expect(variableTokens('Hola {{nombre}}, {{ fecha }} y {{nombre}}')).toEqual(
      ['nombre', 'fecha']
    );
    expect(hasNamedVariables('Hola {{nombre}}')).toBe(true);
    expect(hasNamedVariables('Hola {{1}}')).toBe(false);
    expect(hasNamedVariables('sin variables')).toBe(false);
  });

  it('accepts lowercase names with digits and underscores that start with a letter', () => {
    expect(isValidVariableName('nombre_cliente2')).toBe(true);
    expect(isValidVariableName('Nombre')).toBe(false);
    expect(isValidVariableName('2fecha')).toBe(false);
    expect(isValidVariableName('con-guion')).toBe(false);
  });

  it('validates a named body: one example per name, no mix, no bad name, no edge variable', () => {
    const form = validForm();

    form.body.text = 'Hola {{nombre}}, tu cita es el {{fecha}}.';
    form.body.examples = ['Ana', ''];
    expect(validateForm(form)['body.examples']).toBe('EXAMPLE_REQUIRED');
    form.body.examples = ['Ana', 'lunes'];
    expect(validateForm(form)).toEqual({});

    form.body.text = 'Hola {{nombre}} y {{2}} fin';
    expect(validateForm(form)['body.text']).toBe('VARIABLES_MIXED');
    form.body.text = 'Hola {{Nombre}} fin';
    expect(validateForm(form)['body.text']).toBe('VARIABLE_NAME_INVALID');
    form.body.text = '{{nombre}} hola';
    expect(validateForm(form)['body.text']).toBe('VARIABLE_AT_EDGE');
  });

  it('allows one named variable in the header, with its example', () => {
    const form = validForm();
    form.header.format = 'TEXT';
    form.header.text = 'Cita de {{nombre}}';
    form.header.examples = [''];

    expect(validateForm(form)['header.example']).toBe('EXAMPLE_REQUIRED');
    form.header.examples = ['Ana'];
    expect(validateForm(form)).toEqual({});
    form.header.text = '{{nombre}} {{fecha}}';
    expect(validateForm(form)['header.text']).toBe('HEADER_ONE_VARIABLE');
  });

  it('builds the payload and the preview values by name', () => {
    const form = validForm();
    form.body.text = 'Hola {{nombre}}, tu cita es el {{fecha}}.';
    form.body.examples = ['Ana', 'lunes', 'sobra'];

    expect(buildPayload(form).body.examples).toEqual(['Ana', 'lunes']);
    expect(previewVariables(form)).toEqual({ nombre: 'Ana', fecha: 'lunes' });
  });

  it('reads the named examples of a synced template back in the order of its variables', () => {
    const form = formFromTemplate(
      {
        name: 'cita',
        language: 'es',
        parameter_format: 'NAMED',
        components: [
          {
            type: 'BODY',
            text: 'Hola {{nombre}}, es el {{fecha}}.',
            example: {
              body_text_named_params: [
                { param_name: 'fecha', example: 'lunes' },
                { param_name: 'nombre', example: 'Ana' },
              ],
            },
          },
        ],
      },
      3
    );

    expect(form.body.examples).toEqual(['Ana', 'lunes']);
    expect(validateForm(form, { isEdit: true })).toEqual({});
  });
});

describe('editing a synced template', () => {
  const synced = {
    name: 'recordatorio_cita',
    language: 'es',
    category: 'UTILITY',
    status: 'APPROVED',
    components: [
      {
        type: 'HEADER',
        format: 'TEXT',
        text: 'Cita {{1}}',
        example: { header_text: ['lunes'] },
      },
      { type: 'BODY', text: 'Hola {{1}}.', example: { body_text: [['Ana']] } },
      { type: 'FOOTER', text: 'Gracias' },
      {
        type: 'BUTTONS',
        buttons: [
          { type: 'QUICK_REPLY', text: 'Confirmar' },
          {
            type: 'URL',
            text: 'Ver',
            url: 'https://example.com/{{1}}',
            example: ['https://example.com/9'],
          },
        ],
      },
    ],
  };

  it('rebuilds the form from the template', () => {
    const form = formFromTemplate(synced, 3);

    expect(form).toMatchObject({
      inboxId: 3,
      name: 'recordatorio_cita',
      category: 'UTILITY',
    });
    expect(form.header).toMatchObject({
      format: 'TEXT',
      text: 'Cita {{1}}',
      examples: ['lunes'],
    });
    expect(form.body.examples).toEqual(['Ana']);
    expect(form.buttons[1]).toMatchObject({
      type: 'URL',
      url: 'https://example.com/{{1}}',
      examples: ['https://example.com/9'],
    });
    expect(validateForm(form, { isEdit: true })).toEqual({});
  });

  it('says which templates the form can express', () => {
    expect(isEditable(synced)).toBe(true);
    expect(
      isEditable({
        components: [
          { type: 'BODY', text: 'x' },
          { type: 'BUTTONS', buttons: [{ type: 'FLOW', text: 'Abrir' }] },
        ],
      })
    ).toBe(false);
    expect(isEditable({ components: [{ type: 'CAROUSEL', cards: [] }] })).toBe(
      false
    );
    expect(isEditable({})).toBe(false);
  });

  it('follows the Meta rules for each status', () => {
    expect(editRules('APPROVED')).toEqual({
      canEdit: true,
      categoryLocked: true,
    });
    expect(editRules('REJECTED')).toEqual({
      canEdit: true,
      categoryLocked: false,
    });
    expect(editRules('PENDING')).toEqual({
      canEdit: false,
      categoryLocked: false,
    });
  });
});
