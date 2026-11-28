import { describe, expect, it } from 'vitest';

import Form from '../Form.vue';

const getValidation = Form.methods.getValidation;

const validationFor = (field, required) =>
  getValidation.call(
    {
      isContactFieldRequired: () => required,
    },
    field
  );

describe('PreChat Form getValidation', () => {
  it('returns accepted for a required checkbox', () => {
    expect(validationFor({ type: 'checkbox', name: 'checkbox' }, true)).toEqual(
      [['accepted']]
    );
  });

  it('returns optional for an optional checkbox', () => {
    expect(
      validationFor({ type: 'checkbox', name: 'checkbox' }, false)
    ).toEqual([['optional']]);
  });

  it('returns required for a required text field', () => {
    expect(validationFor({ type: 'text', name: 'text' }, true)).toEqual([
      ['required'],
    ]);
  });

  it('combines required and type-specific validation rules', () => {
    expect(
      validationFor({ type: 'email', name: 'emailAddress' }, true)
    ).toEqual([['required'], ['email']]);
  });
});

describe('PreChat Form contact presence', () => {
  const preChatFields = [
    { name: 'fullName' },
    { name: 'emailAddress' },
    { name: 'phoneNumber' },
  ];

  it('skips the name for an identified contact without receiving the identifier', () => {
    const fields = Form.computed.filteredPreChatFields.call({
      currentUser: {
        has_identifier: true,
        has_email: false,
        has_phone_number: false,
      },
      preChatFields,
    });
    expect(fields).toEqual([{ name: 'emailAddress' }, { name: 'phoneNumber' }]);
  });

  it('asks an anonymous contact for their details', () => {
    const fields = Form.computed.filteredPreChatFields.call({
      currentUser: {
        has_identifier: false,
        has_email: false,
        has_phone_number: false,
      },
      preChatFields,
    });
    expect(fields).toEqual(preChatFields);
  });

  it('skips details that are already present', () => {
    const fields = Form.computed.filteredPreChatFields.call({
      currentUser: {
        has_identifier: false,
        has_email: true,
        has_phone_number: true,
      },
      preChatFields,
    });
    expect(fields).toEqual([]);
  });
});
