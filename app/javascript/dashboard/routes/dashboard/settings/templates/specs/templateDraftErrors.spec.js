import { createI18n } from 'vue-i18n';
import english from 'dashboard/i18n/locale/en/whatsappTemplateMgmt.json';
import spanish from 'dashboard/i18n/locale/es/whatsappTemplateMgmt.json';
import { templateDraftError } from '../templateDraftErrors';

describe.each(['en', 'es'])('draft errors in %s', locale => {
  const { t, te } = createI18n({
    legacy: false,
    locale,
    messages: { en: english, es: spanish },
  }).global;

  it.each([
    { error: 'identity_conflict' },
    { error: 'invalid_draft', details: { name: ['has already been taken'] } },
    { error: 'invalid_draft', details: { name: ['ya está en uso'] } },
  ])('explains uniqueness within the WhatsApp account and language', data => {
    const result = templateDraftError({ response: { data } }, t, te);
    expect(result.message).toBe(
      t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.IDENTITY_CONFLICT')
    );
    expect(result.fields.name).toBe(result.message);
    expect(result.message).toContain(
      locale === 'es'
        ? 'cuenta de WhatsApp e idioma'
        : 'WhatsApp account and language'
    );
  });

  it('translates details, including fields without an editable control, without exposing server keys', () => {
    const result = templateDraftError(
      {
        response: {
          data: {
            error: 'invalid_draft',
            details: {
              waba_id: ['invalid'],
              title: ['invalid'],
              created_by: ['invalid'],
            },
          },
        },
      },
      t,
      te
    );
    expect(result.fields).toEqual({
      inboxId: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.inboxId'),
      title: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.title'),
    });
    expect(result.message).not.toMatch(
      /waba_id|created_by|WHATSAPP_TEMPLATE_MGMT/
    );
    expect(
      templateDraftError(
        {
          response: {
            data: {
              error: 'invalid_draft',
              details: { created_by: ['invalid'] },
            },
          },
        },
        t,
        te
      ).message
    ).toBe(t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.INVALID_DRAFT'));
  });
});
