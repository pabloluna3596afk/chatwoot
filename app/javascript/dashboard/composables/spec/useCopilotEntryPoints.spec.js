import {
  getCopilotEntryPoints,
  isCopilotConversationSelected,
} from 'dashboard/composables/useCopilotEntryPoints';

describe('useCopilotEntryPoints decisions', () => {
  it.each([
    ['conversation without a selected message view', 'home', {}, false],
    ['selected conversation', 'home', { conversationId: '42' }, true],
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
      'selected conversation, contact panel closed',
      true,
      false,
      false,
      false,
      true,
    ],
    [
      'selected conversation, contact panel open',
      true,
      true,
      false,
      true,
      false,
    ],
    ['selected conversation, Copilot open', true, false, true, false, true],
    ['contacts with bulk selection', false, false, false, true, false],
    ['calendar', false, false, false, true, false],
    ['Captain disabled', false, false, false, false, false, false],
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
