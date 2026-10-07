import {
  collectAnswers,
  evaluateVisibility,
  validateAnswers,
} from '../flowAnswers';

describe('Flow answer rules', () => {
  it('evaluates equality, inequality and booleans with the existing visibility semantics', () => {
    const block = { visible_when: { key: 'opt', op: 'equals', value: 'true' } };
    expect(evaluateVisibility(block, { opt: true })).toBe(true);
    expect(evaluateVisibility(block, {})).toBe(false);
    block.visible_when.op = 'not_equals';
    expect(evaluateVisibility(block, {})).toBe(true);
    expect(evaluateVisibility(block, { opt: true })).toBe(false);
  });

  it('discards hidden answers and dependent answers, omits empty optionals and keeps false/zero', () => {
    const definition = {
      screens: [
        {
          blocks: [
            { key: 'topic', type: 'dropdown' },
            {
              key: 'detail',
              type: 'short_text',
              visible_when: { key: 'topic', op: 'equals', value: 'other' },
            },
            {
              key: 'dependent',
              type: 'long_text',
              visible_when: { key: 'detail', op: 'equals', value: 'yes' },
            },
            { key: 'empty', type: 'short_text' },
            { key: 'zero', type: 'short_text', input: 'number' },
            { key: 'consent', type: 'optin' },
          ],
        },
      ],
    };
    expect(
      collectAnswers(definition, {
        topic: 'general',
        detail: 'yes',
        dependent: 'stale',
        empty: ' ',
        zero: 0,
        consent: false,
      })
    ).toEqual({ topic: 'general', zero: '0', consent: false });
  });

  it('validates only visible fields and checks required, email and selection limits', () => {
    const screen = {
      blocks: [
        { key: 'name', type: 'short_text', required: true },
        { key: 'email', type: 'short_text', input: 'email' },
        { key: 'consent', type: 'optin', required: true },
        {
          key: 'hidden',
          type: 'short_text',
          required: true,
          visible_when: { key: 'name', op: 'equals', value: 'other' },
        },
        { key: 'options', type: 'checkbox', min: 2, max: 3 },
      ],
    };
    expect(
      validateAnswers(screen, {
        email: 'wrong',
        consent: false,
        options: ['a'],
      })
    ).toEqual({
      name: 'REQUIRED',
      email: 'EMAIL',
      consent: 'REQUIRED',
      options: 'SELECTION',
    });
  });
});
