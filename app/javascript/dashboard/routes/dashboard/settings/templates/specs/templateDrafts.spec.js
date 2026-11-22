import { emptyForm, newButton } from '../templateForm';
import {
  currentSubmission,
  draftFromForm,
  formFromDraft,
  draftRow,
  hasOpaqueComponents,
  libraryPreview,
} from '../templateDrafts';
import en from 'dashboard/i18n/locale/en/whatsappTemplateMgmt.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplateMgmt.json';

describe('Local draft definitions', () => {
  it.each([en, es])(
    'keeps the compact local notice aligned with the translated review action',
    messages => {
      const drafts = messages.WHATSAPP_TEMPLATE_MGMT.DRAFTS;
      expect(drafts.LOCAL_SAVE_HELP).toContain(drafts.SUBMIT);
      expect(drafts.LOCAL_SAVE_HELP).not.toContain('?');
      expect(drafts.LOCAL_SAVE_HELP).not.toContain('\uFFFD');
      expect(drafts.LOCAL_DRAFT).not.toBe('');
    }
  );

  it('uses the library language for reopening, saving and previewing conflicting form languages', () => {
    const library = {
      template_name: 'appointment',
      language: 'es',
      preview: { body: 'Tu cita' },
    };
    const form = formFromDraft(
      { language: 'en_US', definition: { library } },
      []
    );
    expect(form.language).toBe('es');
    form.language = 'en_US';
    expect(draftFromForm(form, []).language).toBe('es');
    expect(libraryPreview(form)).toMatchObject({ language: 'es' });
    expect(libraryPreview(form).components).toContainEqual({
      type: 'BODY',
      text: 'Tu cita',
    });
    expect(
      draftRow({ language: 'en_US', definition: { library } }, []).language
    ).toBe('es');
  });
  const inboxes = [
    {
      id: 7,
      channel_id: 70,
      name: 'Support',
      provider_config: { business_account_id: 'waba-a' },
    },
    {
      id: 8,
      channel_id: 80,
      name: 'Sales',
      provider_config: { business_account_id: 'waba-a' },
    },
  ];

  it('round-trips incomplete content, examples, bindings, buttons and opaque components without remote handles', () => {
    const form = emptyForm();
    Object.assign(form, {
      name: '',
      inboxId: 7,
      variableBindings: { nombre: 'contact.name' },
    });
    form.header = {
      format: 'IMAGE',
      text: '',
      examples: [],
      handle: 'must-not-be-sent',
      fileName: 'photo.png',
    };
    form.body = {
      text: ' Unfinished {{nombre}} ',
      examples: ['Ana', 'extra example'],
    };
    form.buttons = [
      {
        ...newButton('PHONE_NUMBER'),
        text: 'Call',
        phoneNumber: '+593999999999',
      },
      {
        ...newButton('URL'),
        text: 'Open',
        url: 'https://example.com/{{1}}',
        examples: ['order'],
      },
    ];
    form.preserved.components.push({
      position: 2,
      component: { type: 'CAROUSEL', cards: [] },
    });
    const attributes = draftFromForm(form, inboxes);
    expect(attributes.preferred_channel_id).toBe(70);
    expect(attributes.name).toBeNull();
    expect(attributes.definition.header).not.toHaveProperty('handle');
    const reopened = formFromDraft(
      { ...attributes, media: { filename: 'photo.png' } },
      inboxes
    );
    expect(reopened.inboxId).toBe(7);
    expect(reopened.body).toEqual(form.body);
    expect(reopened.buttons).toEqual(form.buttons);
    expect(reopened.preserved).toEqual(form.preserved);
    expect(reopened.variableBindings).toEqual(form.variableBindings);
    expect(hasOpaqueComponents(reopened)).toBe(true);
  });

  it('uses only the current revision for remote status and groups its WABA destinations', () => {
    const record = {
      ...draftFromForm({ ...emptyForm(), inboxId: 7 }, inboxes),
      id: 31,
      lock_version: 3,
      status: 'draft',
      submissions: [{ revision: 2, remote_status: 'APPROVED' }],
    };
    expect(currentSubmission(record)).toBeUndefined();
    expect(draftRow(record, inboxes)).toMatchObject({
      key: 'draft-31',
      remoteStatus: undefined,
      inboxNames: 'Support, Sales',
    });
    record.submissions.push({ revision: 3, remote_status: 'IN_APPEAL' });
    expect(draftRow(record, inboxes).remoteStatus).toBe('IN_APPEAL');
  });

  it('has matching English/Spanish draft keys and exact product copy', () => {
    const english = en.WHATSAPP_TEMPLATE_MGMT.DRAFTS;
    const spanish = es.WHATSAPP_TEMPLATE_MGMT.DRAFTS;
    expect(Object.keys(english).sort()).toEqual(Object.keys(spanish).sort());
    expect(Object.keys(english.STATUS).sort()).toEqual(
      Object.keys(spanish.STATUS).sort()
    );
    expect(spanish.SAVED).toBe(
      'Borrador guardado. Todavía no se ha enviado a Meta.'
    );
    expect(spanish.NO_DESTINATION_HELP).toBe(
      'Puedes guardar sin canal. Elige una cuenta de WhatsApp antes de enviar a revisión.'
    );
  });

  it('infers the original format when a server copy has no explicit parameter format', () => {
    const record = {
      definition: { body: { text: 'Hello {{1}}.', examples: ['Ana'] } },
      parameter_format: null,
    };
    expect(formFromDraft(record, []).parameterFormat).toBe('POSITIONAL');
    record.definition.body.text = 'Hello {{nombre}}.';
    expect(formFromDraft(record, []).parameterFormat).toBe('NAMED');
  });
  it('round-trips library mode without editable body and renders the saved Meta preview in the table', () => {
    const library = {
      template_name: 'appointment',
      language: 'es',
      button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '' }],
      preview: {
        body: 'Tu cita {{1}}',
        buttons: [{ type: 'PHONE_NUMBER', text: 'Llamar' }],
      },
    };
    const record = {
      id: 31,
      name: 'my_appointment',
      language: 'es',
      category: 'UTILITY',
      definition: { library },
      submissions: [],
    };
    const form = formFromDraft(record, []);
    expect(form.body.text).toBe('');
    expect(draftFromForm(form, []).definition).toEqual({ library });
    form.library.button_inputs[0].phone_number = '+593999999999';
    expect(record.definition.library.button_inputs[0].phone_number).toBe('');
    expect(draftRow(record, []).components).toContainEqual({
      type: 'BODY',
      text: 'Tu cita {{1}}',
    });
  });
  it('reopens a library definition with the documented omitted button inputs', () => {
    const form = formFromDraft(
      {
        definition: {
          library: { template_name: 'appointment', language: 'es' },
        },
      },
      []
    );
    expect(form.library.button_inputs).toEqual([]);
    expect(draftFromForm(form, []).definition.library).toEqual({
      template_name: 'appointment',
      language: 'es',
      button_inputs: [],
    });
  });
});
