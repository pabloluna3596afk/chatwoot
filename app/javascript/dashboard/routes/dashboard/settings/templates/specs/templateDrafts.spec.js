import { emptyForm, newButton } from '../templateForm';
import {
  currentSubmission,
  draftFromForm,
  formFromDraft,
  draftRow,
  hasOpaqueComponents,
} from '../templateDrafts';
import en from 'dashboard/i18n/locale/en/whatsappTemplateMgmt.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplateMgmt.json';

describe('Local draft definitions', () => {
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
});
