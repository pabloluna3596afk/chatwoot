import {
  isOnMentionsView,
  isOnFoldersView,
  isOnParticipatingView,
  isOnCaptainView,
} from '../actionHelpers';

describe('#isOnMentionsView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnMentionsView({ route: { name: 'conversation_mentions' } })).toBe(
      true
    );
    expect(isOnMentionsView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnFoldersView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnFoldersView({ route: { name: 'folder_conversations' } })).toBe(
      true
    );
    expect(
      isOnFoldersView({ route: { name: 'conversations_through_folders' } })
    ).toBe(true);
    expect(isOnFoldersView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnParticipatingView', () => {
  it('return valid responses when passing the state', () => {
    expect(
      isOnParticipatingView({ route: { name: 'conversation_participating' } })
    ).toBe(true);
    expect(
      isOnParticipatingView({
        route: { name: 'conversation_through_participating' },
      })
    ).toBe(true);
    expect(
      isOnParticipatingView({ route: { name: 'conversation_messages' } })
    ).toBe(false);
  });
});

describe('#isOnCaptainView', () => {
  it('returns true on the AI list and on a conversation opened from it', () => {
    expect(isOnCaptainView({ route: { name: 'conversation_ai' } })).toBe(true);
    expect(
      isOnCaptainView({ route: { name: 'conversation_through_ai' } })
    ).toBe(true);
  });
  it('returns false on any other route', () => {
    expect(isOnCaptainView({ route: { name: 'home' } })).toBe(false);
  });
});
