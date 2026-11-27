import {
  aggregateState,
  buildTemplateState,
  mapTemplateState,
  TEMPLATE_STATES,
} from '../useCitasPanel';

const combinations = (length, values = TEMPLATE_STATES) =>
  length === 1
    ? values.map(value => [value])
    : combinations(length - 1, values).flatMap(prefix =>
        values.map(value => [...prefix, value])
      );

describe('template state aggregation', () => {
  it.each(combinations(3))(
    'chooses the highest-priority state from %j',
    states => {
      const priority = ['approved', 'review', 'unsent', 'rejected', 'failed'];
      const expected = [...states].sort(
        (left, right) => priority.indexOf(right) - priority.indexOf(left)
      )[0];
      expect(aggregateState(states)).toBe(expected);
    }
  );

  it.each([
    [{ state: 'usable' }, 'approved'],
    [
      { state: 'incompatible', submission: { remote_status: 'APPROVED' } },
      'approved',
    ],
    [{ state: 'pending_approval' }, 'review'],
    [{ state: 'not_submitted', submission: { status: 'submitted' } }, 'review'],
    [
      { state: 'incompatible', submission: { remote_status: 'PENDING' } },
      'review',
    ],
    [
      { state: 'incompatible', submission: { remote_status: 'REJECTED' } },
      'rejected',
    ],
    [{ state: 'submission_failed' }, 'failed'],
    [{ state: 'not_submitted', submission: { status: 'failed' } }, 'failed'],
    [{ state: 'missing' }, 'unsent'],
    [{ state: 'not_submitted' }, 'unsent'],
  ])('maps %j to %s', (destination, state) => {
    expect(mapTemplateState(destination)).toBe(state);
  });

  it('builds template rows and accounts in first-destination order', () => {
    const data = {
      results: {
        confirmation: {
          draft_exists: true,
          destinations: [
            {
              waba_id: 'a',
              state: 'usable',
              channels: [{ name: 'Sales', phone_number: '+100' }],
            },
            {
              waba_id: 'b',
              state: 'incompatible',
              reason: 'rejected',
              submission: {
                remote_status: 'REJECTED',
                remote_reason: 'Too long',
              },
              channels: [{ name: 'Support', phone_number: '+200' }],
            },
            {
              waba_id: 'c',
              state: 'not_submitted',
              channels: [{ name: 'Clinic', phone_number: '+300' }],
            },
          ],
        },
      },
    };
    const result = buildTemplateState(data);
    expect(result.accounts.map(account => account.waba_id)).toEqual([
      'a',
      'b',
      'c',
    ]);
    expect(result.functions).toHaveLength(3);
    expect(result.functions[0].counts).toMatchObject({
      approved: 1,
      rejected: 1,
      unsent: 1,
    });
    expect(result.functions[0].aggregate).toBe('rejected');
    expect(result.functions[0].perWaba[1].reason).toBe('Too long');
    expect(result.functions[1].perWaba.map(item => item.state)).toEqual([
      'unsent',
      'unsent',
      'unsent',
    ]);
  });

  it('handles zero and five WhatsApp accounts', () => {
    expect(buildTemplateState({ results: {} }).accounts).toEqual([]);
    const results = Object.fromEntries(
      ['confirmation', 'cancellation', 'reminder'].map(key => [
        key,
        {
          destinations: Array.from({ length: 5 }, (_, index) => ({
            waba_id: String(index + 1),
            state: index === 0 ? 'usable' : 'not_submitted',
          })),
        },
      ])
    );
    const state = buildTemplateState({ results });

    expect(state.accounts).toHaveLength(5);
    expect(state.functions[0].counts).toMatchObject({ approved: 1, unsent: 4 });
  });
});
