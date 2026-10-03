import {
  getConversationAssigneeType,
  inferAssigneeType,
  isAIAssigneeType,
  isHumanAssigneeMeta,
  isBotAssigneeMeta,
} from '../assigneeHelper';

describe('assigneeHelper with Captain as an assignee', () => {
  const captainMeta = {
    assignee: { id: 7, name: 'Captain' },
    assignee_type: 'Captain::Assistant',
  };

  it('keeps the Captain assignee type instead of falling back to a person', () => {
    expect(getConversationAssigneeType(captainMeta)).toBe('Captain::Assistant');
    expect(
      inferAssigneeType({ id: 7, assignee_type: 'Captain::Assistant' })
    ).toBe('Captain::Assistant');
  });

  it('does not count Captain as a human or as the inbox bot', () => {
    expect(isHumanAssigneeMeta(captainMeta)).toBe(false);
    expect(isBotAssigneeMeta(captainMeta)).toBe(false);
  });

  it('tells AI owners from people', () => {
    expect(isAIAssigneeType('Captain::Assistant')).toBe(true);
    expect(isAIAssigneeType('AgentBot')).toBe(true);
    expect(isAIAssigneeType('User')).toBe(false);
  });
});
