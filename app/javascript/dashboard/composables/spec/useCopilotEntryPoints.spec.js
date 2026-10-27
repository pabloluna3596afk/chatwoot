import {
  getCopilotEntryPoints,
  isCopilotConversationSelected,
} from 'dashboard/composables/useCopilotEntryPoints';

describe('useCopilotEntryPoints decisions', () => {
  it.each([
    ['conversation without a selected message view', 'home', {}, false],
    ['selected conversation', 'home', { conversationId: '42' }, true],
    [
      'selected legacy conversation route',
      'inbox_conversation',
      { conversation_id: '42' },
      true,
    ],
    [
      'selected inbox conversation',
      'inbox_view_conversation',
      { id: '42' },
      true,
    ],
    ['inbox list', 'inbox_view', {}, false],
    ['contacts selection', 'contacts_dashboard', { id: '42' }, false],
    ['calendar', 'calendars_dashboard_index', {}, false],
  ])('recognizes route state: %s', (_label, name, params, expected) => {
    expect(isCopilotConversationSelected({ name, params })).toBe(expected);
  });

  it.each([
    [
      'conversation, contact panel closed, Copilot minimized',
      true,
      false,
      false,
      false,
      true,
    ],
    [
      'conversation, contact panel closed, Copilot open',
      true,
      false,
      true,
      false,
      true,
    ],
    [
      'conversation, contact panel open, Copilot minimized',
      true,
      true,
      false,
      true,
      false,
    ],
    [
      'conversation, contact panel open, Copilot open',
      true,
      true,
      true,
      false,
      false,
    ],
    ['contacts with bulk selection', false, false, false, true, false],
    ['calendar', false, false, false, true, false],
    [
      'Captain disabled on a selected conversation',
      true,
      false,
      false,
      false,
      false,
      false,
    ],
  ])(
    '%s',
    (
      _label,
      conversationSelected,
      contactSidebarOpen,
      copilotPanelOpen,
      showLauncher,
      showSidepanelCopilotTab,
      enabled = true
    ) => {
      expect(
        getCopilotEntryPoints({
          enabled,
          conversationSelected,
          contactSidebarOpen,
          copilotPanelOpen,
        })
      ).toEqual({ showLauncher, showSidepanelCopilotTab });
    }
  );
});
