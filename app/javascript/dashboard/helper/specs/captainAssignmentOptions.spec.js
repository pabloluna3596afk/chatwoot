import {
  buildCaptainOptions,
  withAIAssigneesFirst,
} from '../captainAssignmentOptions';
import { pinnedInboxIds } from '../captainAssignment';

const t = key => key;
const assistants = [
  { id: 7, name: 'Sales' },
  { id: 8, name: 'Support' },
];
const inboxes = [
  { id: 1, captain_assistant: assistants[0] },
  { id: 2, captain_assistant: assistants[1] },
  { id: 3, captain_assistant: assistants[0] },
  { id: 4, captain_assistant: null },
];

describe('Captain assignment options', () => {
  it.each([
    [[], ['captain']],
    [[1], ['captain:7']],
    [
      [1, 2, 3],
      ['captain:7', 'captain:8'],
    ],
    [[4], ['captain']],
    [
      [1, 4],
      ['captain:7', 'captain'],
    ],
  ])('uses pinned inboxes %j without duplicate assistants', (inboxIds, ids) => {
    expect(
      buildCaptainOptions({ inboxIds, inboxes, assistants, t }).map(
        option => option.id
      )
    ).toEqual(ids);
  });

  it('shows the missing-assistant note beside Captain', () => {
    expect(
      buildCaptainOptions({ inboxIds: [4], inboxes, assistants, t })[0]
    ).toMatchObject({
      id: 'captain',
      description: 'CAPTAIN.ASSIGNMENT.NO_ASSISTANT',
    });
  });

  it('uses the inbox assistant name while the assistant list loads', () => {
    expect(buildCaptainOptions({ inboxIds: [1], inboxes, t })[0].name).toBe(
      'Sales'
    );
  });

  it('pins only equality conditions without OR', () => {
    const condition = {
      attribute_key: 'inbox_id',
      filter_operator: 'equal_to',
      values: [{ id: 1 }, { id: 2 }],
      query_operator: 'and',
    };
    expect(pinnedInboxIds([condition])).toEqual([1, 2]);
    expect(
      pinnedInboxIds([{ ...condition, filter_operator: 'not_equal_to' }])
    ).toEqual([]);
    expect(
      pinnedInboxIds([
        condition,
        { attribute_key: 'status', query_operator: 'or' },
      ])
    ).toEqual([]);
  });

  it('keeps None before Captain, other assistants and people without mutating the source', () => {
    const none = { id: 0 };
    const person = { id: 1, assignee_type: 'User' };
    const bot = { id: 1, assignee_type: 'AgentBot' };
    const captain = { id: 1, assignee_type: 'Captain::Assistant' };
    const agents = [person, bot, captain];
    expect([none, ...withAIAssigneesFirst(agents)]).toEqual([
      none,
      captain,
      bot,
      person,
    ]);
    expect(agents).toEqual([person, bot, captain]);
  });
});
