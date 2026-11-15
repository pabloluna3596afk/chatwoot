import { ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useBusinessRulesStatusGuard } from 'dashboard/composables/useBusinessRulesStatusGuard';
import { useBulkActions } from '../useBulkActions';

vi.mock('vuex', () => ({ useStore: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useMapGetter: vi.fn() }));
vi.mock('dashboard/composables/useBusinessRulesStatusGuard', () => ({
  useBusinessRulesStatusGuard: vi.fn(),
}));

describe('useBulkActions agent assignment', () => {
  let store;
  let selectedConversations;

  beforeEach(() => {
    store = { dispatch: vi.fn().mockResolvedValue(undefined) };
    selectedConversations = ref([10, 20]);
    useStore.mockReturnValue(store);
    useMapGetter.mockReturnValue(selectedConversations);
    useI18n.mockReturnValue({ t: key => key });
    useBusinessRulesStatusGuard.mockReturnValue({ checkStatusChange: vi.fn() });
  });

  it.each([
    ['a Captain assistant with its own type', 'Captain::Assistant'],
    ['an agent bot with its type', 'AgentBot'],
    ['a person as User', undefined],
  ])('assigns %s to several conversations', async (_, assigneeType) => {
    const { onAssignAgent } = useBulkActions();

    await onAssignAgent({
      id: 1,
      name: 'Assignee',
      assignee_type: assigneeType,
    });

    expect(store.dispatch.mock.calls).toEqual([
      [
        'assignAgent',
        {
          conversationId: 10,
          agentId: 1,
          assigneeType: assigneeType || 'User',
        },
      ],
      [
        'assignAgent',
        {
          conversationId: 20,
          agentId: 1,
          assigneeType: assigneeType || 'User',
        },
      ],
      ['bulkActions/clearSelectedConversationIds'],
    ]);
    expect(useAlert).toHaveBeenCalledWith('BULK_ACTION.ASSIGN_SUCCESFUL');
  });

  it.each([null, { id: 0, name: 'None' }])(
    'unassigns when no agent is given (%s)',
    async agent => {
      const { onAssignAgent } = useBulkActions();

      await onAssignAgent(agent);

      expect(store.dispatch.mock.calls).toEqual([
        ['assignAgent', { conversationId: 10, agentId: null }],
        ['assignAgent', { conversationId: 20, agentId: null }],
        ['bulkActions/clearSelectedConversationIds'],
      ]);
    }
  );

  it.each([30, [30, 40]])(
    'assigns Captain from the context menu to %s',
    async conversationId => {
      const { onAssignAgent } = useBulkActions();

      await onAssignAgent(
        { id: 1, name: 'Aurora', assignee_type: 'Captain::Assistant' },
        conversationId
      );

      const ids = Array.isArray(conversationId)
        ? conversationId
        : [conversationId];
      expect(store.dispatch.mock.calls).toEqual([
        ...ids.map(id => [
          'assignAgent',
          {
            conversationId: id,
            agentId: 1,
            assigneeType: 'Captain::Assistant',
          },
        ]),
        ['bulkActions/clearSelectedConversationIds'],
      ]);
      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.SUCCESFUL'
      );
    }
  );

  it.each([null, 30])(
    'shows the existing error and preserves selection on 422 (context %s)',
    async conversationId => {
      store.dispatch.mockRejectedValue({
        response: {
          status: 422,
          data: { error: 'assignment_not_applied', reason: 'not_assignable' },
        },
      });
      const { onAssignAgent } = useBulkActions();

      await onAssignAgent(
        { id: 1, name: 'Aurora', assignee_type: 'Captain::Assistant' },
        conversationId
      );

      expect(useAlert).toHaveBeenCalledExactlyOnceWith(
        'BULK_ACTION.ASSIGN_FAILED'
      );
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'bulkActions/clearSelectedConversationIds'
      );
      expect(selectedConversations.value).toEqual([10, 20]);
      expect(
        store.dispatch.mock.calls.every(([action]) => action === 'assignAgent')
      ).toBe(true);
    }
  );
});
