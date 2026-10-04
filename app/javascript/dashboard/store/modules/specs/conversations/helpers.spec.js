import {
  findPendingMessageIndex,
  applyPageFilters,
  filterByInbox,
  filterByTeam,
  filterByLabel,
  filterByUnattended,
  filterByCaptain,
  matchesUnassignedTab,
} from '../../conversations/helpers';

const conversationList = [
  {
    id: 1,
    inbox_id: 2,
    status: 'open',
    meta: {},
    labels: ['sales', 'dev'],
  },
  {
    id: 2,
    inbox_id: 2,
    status: 'open',
    meta: {},
    labels: ['dev'],
  },
  {
    id: 11,
    inbox_id: 3,
    status: 'resolved',
    meta: { team: { id: 5 } },
    labels: [],
  },
  {
    id: 22,
    inbox_id: 4,
    status: 'pending',
    meta: { team: { id: 5 } },
    labels: ['sales'],
  },
];

describe('#findPendingMessageIndex', () => {
  it('returns the correct index of pending message with id', () => {
    const chat = {
      messages: [{ id: 1, status: 'progress' }],
    };
    const message = { echo_id: 1 };
    expect(findPendingMessageIndex(chat, message)).toEqual(0);
  });

  it('returns -1 if pending message with id is not present', () => {
    const chat = {
      messages: [{ id: 1, status: 'progress' }],
    };
    const message = { echo_id: 2 };
    expect(findPendingMessageIndex(chat, message)).toEqual(-1);
  });
});

describe('#applyPageFilters', () => {
  describe('#filter-team', () => {
    it('returns true if conversation has team and team filter is active', () => {
      const filters = {
        status: 'resolved',
        teamId: 5,
      };
      expect(applyPageFilters(conversationList[2], filters)).toEqual(true);
    });
    it('returns true if conversation has no team and team filter is active', () => {
      const filters = {
        status: 'open',
        teamId: 5,
      };
      expect(applyPageFilters(conversationList[0], filters)).toEqual(false);
    });
  });

  describe('#filter-inbox', () => {
    it('returns true if conversation has inbox and inbox filter is active', () => {
      const filters = {
        status: 'pending',
        inboxId: 4,
      };
      expect(applyPageFilters(conversationList[3], filters)).toEqual(true);
    });
    it('returns true if conversation has no inbox and inbox filter is active', () => {
      const filters = {
        status: 'open',
        inboxId: 5,
      };
      expect(applyPageFilters(conversationList[0], filters)).toEqual(false);
    });
  });

  describe('#filter-labels', () => {
    it('returns true if conversation has labels and labels filter is active', () => {
      const filters = {
        status: 'open',
        labels: ['dev'],
      };
      expect(applyPageFilters(conversationList[0], filters)).toEqual(true);
    });
    it('returns true if conversation has no inbox and inbox filter is active', () => {
      const filters = {
        status: 'open',
        labels: ['dev'],
      };
      expect(applyPageFilters(conversationList[2], filters)).toEqual(false);
    });
  });

  describe('#filter-status', () => {
    it('returns true if conversation has status and status filter is active', () => {
      const filters = {
        status: 'open',
      };
      expect(applyPageFilters(conversationList[1], filters)).toEqual(true);
    });
    it('returns true if conversation has status and status filter is all', () => {
      const filters = {
        status: 'all',
      };
      expect(applyPageFilters(conversationList[1], filters)).toEqual(true);
    });
  });
});

describe('#filterByInbox', () => {
  it('returns true if conversation has inbox filter active', () => {
    const inboxId = '1';
    const chatInboxId = 1;
    expect(filterByInbox(true, inboxId, chatInboxId)).toEqual(true);
  });
  it('returns false if inbox filter is not active', () => {
    const inboxId = '1';
    const chatInboxId = 13;
    expect(filterByInbox(true, inboxId, chatInboxId)).toEqual(false);
  });
});

describe('#filterByTeam', () => {
  it('returns true if conversation has team and team filter is active', () => {
    const [teamId, chatTeamId] = ['1', 1];
    expect(filterByTeam(true, teamId, chatTeamId)).toEqual(true);
  });
  it('returns false if team filter is not active', () => {
    const [teamId, chatTeamId] = ['1', 12];
    expect(filterByTeam(true, teamId, chatTeamId)).toEqual(false);
  });
});

describe('#filterByLabel', () => {
  it('returns true if conversation has labels and labels filter is active', () => {
    const labels = ['dev', 'cs'];
    const chatLabels = ['dev', 'cs', 'sales'];
    expect(filterByLabel(true, labels, chatLabels)).toEqual(true);
  });
  it('returns false if conversation has not all labels', () => {
    const labels = ['dev', 'cs', 'sales'];
    const chatLabels = ['cs', 'sales'];
    expect(filterByLabel(true, labels, chatLabels)).toEqual(false);
  });
});

describe('#filterByUnattended', () => {
  it('returns true if conversation type is unattended and has no first reply', () => {
    expect(filterByUnattended(true, 'unattended', undefined)).toEqual(true);
  });
  it('returns false if conversation type is not unattended and has no first reply', () => {
    expect(filterByUnattended(false, 'mentions', undefined)).toEqual(false);
  });
  it('returns true if conversation type is unattended and has first reply', () => {
    expect(filterByUnattended(true, 'mentions', 123)).toEqual(true);
  });
});

describe('#filterByCaptain', () => {
  it('keeps only conversations the AI is attending in the AI view', () => {
    expect(filterByCaptain(true, 'captain', 'ai')).toEqual(true);
    expect(filterByCaptain(true, 'captain', 'escalated')).toEqual(false);
    expect(filterByCaptain(true, 'captain', null)).toEqual(false);
  });
  it('does not filter outside the AI view', () => {
    expect(filterByCaptain(true, 'mention', null)).toEqual(true);
    expect(filterByCaptain(true, undefined, 'ai')).toEqual(true);
  });
  it('never turns a rejected conversation into an accepted one', () => {
    expect(filterByCaptain(false, 'captain', 'ai')).toEqual(false);
  });
});

describe('#applyPageFilters in the AI view', () => {
  const aiChat = { id: 1, inbox_id: 1, status: 'pending', captain_state: 'ai' };
  const escalatedChat = {
    id: 2,
    inbox_id: 1,
    status: 'open',
    captain_state: 'escalated',
  };

  it('ignores the status filter', () => {
    const filters = { status: 'open', conversationType: 'captain' };
    expect(applyPageFilters(aiChat, filters)).toEqual(true);
  });
  it('drops escalated conversations', () => {
    const filters = { status: 'all', conversationType: 'captain' };
    expect(applyPageFilters(escalatedChat, filters)).toEqual(false);
  });
  it('still respects the inbox filter', () => {
    const filters = {
      status: 'all',
      inboxId: 2,
      conversationType: 'captain',
    };
    expect(applyPageFilters(aiChat, filters)).toEqual(false);
  });
  it('keeps applying the status filter in the other views (Captain attending reads as open, not pending)', () => {
    const filters = { status: 'pending', conversationType: 'unattended' };
    expect(applyPageFilters(aiChat, filters)).toEqual(false);
  });
});

describe('#matchesUnassignedTab', () => {
  it('leaves out conversations the AI is attending', () => {
    const chat = { meta: {}, captain_state: 'ai' };
    expect(matchesUnassignedTab(chat)).toEqual(false);
  });
  it('includes escalated conversations without a human assignee', () => {
    const chat = { meta: {}, captain_state: 'escalated' };
    expect(matchesUnassignedTab(chat)).toEqual(true);
  });
  it('includes plain unassigned conversations', () => {
    expect(matchesUnassignedTab({ meta: {}, captain_state: null })).toEqual(
      true
    );
  });
  it('leaves out conversations with a human assignee', () => {
    const chat = { meta: { assignee: { id: 1 } }, captain_state: null };
    expect(matchesUnassignedTab(chat)).toEqual(false);
  });
});

describe('#applyPageFilters with Captain attending', () => {
  const attended = {
    id: 99,
    status: 'pending',
    display_status: 'open',
    captain_state: 'ai',
    inbox_id: 1,
    meta: {},
    labels: [],
  };

  it('lists it under open and not under pending', () => {
    expect(applyPageFilters(attended, { status: 'open' })).toBe(true);
    expect(applyPageFilters(attended, { status: 'pending' })).toBe(false);
  });
});
