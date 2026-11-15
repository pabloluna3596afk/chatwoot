import { ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import { useConversationAssignee } from '../useConversationAssignee';

vi.mock('vuex', () => ({ useStore: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAgentsList', () => ({
  useAgentsList: vi.fn(),
}));

describe('useConversationAssignee shared by header and sidebar', () => {
  it('keeps the previous assignee, alerts and releases isAssigning on 422', async () => {
    let rejectAssignment;
    const store = {
      getters: {
        getSelectedChat: {
          id: 10,
          meta: {
            assignee: { id: 1, name: 'Person' },
            assignee_type: 'User',
          },
        },
      },
      dispatch: vi.fn().mockReturnValue(
        new Promise((resolve, reject) => {
          rejectAssignment = reject;
        })
      ),
    };
    useStore.mockReturnValue(store);
    useI18n.mockReturnValue({ t: key => key });
    useAgentsList.mockReturnValue({
      agentsList: ref([]),
      inboxBotAgent: ref(null),
    });
    const { assignedAgent, isAssigning, onClickAssignAgent } =
      useConversationAssignee();
    const previousAssignee = assignedAgent.value;

    onClickAssignAgent({
      id: 1,
      name: 'Aurora',
      assignee_type: 'Captain::Assistant',
    });

    expect(isAssigning.value).toBe(true);
    expect(assignedAgent.value).toEqual(previousAssignee);
    expect(store.dispatch).toHaveBeenCalledExactlyOnceWith('assignAgent', {
      conversationId: 10,
      agentId: 1,
      assigneeType: 'Captain::Assistant',
    });

    rejectAssignment({
      response: {
        status: 422,
        data: { error: 'assignment_not_applied', reason: 'not_assignable' },
      },
    });
    await flushPromises();

    expect(isAssigning.value).toBe(false);
    expect(assignedAgent.value).toEqual(previousAssignee);
    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledExactlyOnceWith(
      'CONVERSATION.CHANGE_AGENT_FAILED'
    );
  });
});
