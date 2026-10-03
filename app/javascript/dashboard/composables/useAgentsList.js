import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getAgentsByUpdatedPresence,
  getSortedAgentsByAvailability,
} from 'dashboard/helper/agentHelper';
import {
  getInboxBotAgent,
  isAIAssigneeType,
} from 'dashboard/helper/assigneeHelper';

/**
 * A composable function that provides a list of agents for assignment.
 *
 * @param {boolean} [includeNoneAgent=true] - Whether to include a 'None' agent option.
 * @param {Object} [options] - Options for the assignable agents list.
 * @param {boolean} [options.includeAIAssignees=false] - Whether to include Agent Bots and the connected Captain assistant.
 * @returns {Object} An object containing the agents list and assignable agents.
 */
export function useAgentsList(
  includeNoneAgent = true,
  { includeAIAssignees = false } = {}
) {
  const { t } = useI18n();
  const currentUser = useMapGetter('getCurrentUser');
  const currentChat = useMapGetter('getSelectedChat');
  const currentAccountId = useMapGetter('getCurrentAccountId');
  const assignable = useMapGetter('inboxAssignableAgents/getAssignableAgents');

  const inboxId = computed(() => currentChat.value?.inbox_id);
  const isAgentSelected = computed(() => currentChat.value?.meta?.assignee);

  /**
   * Creates a 'None' agent object
   * @returns {Object} None agent object
   */
  const createNoneAgent = () => ({
    confirmed: true,
    name: t('AGENT_MGMT.MULTI_SELECTOR.LIST.NONE') || 'None',
    id: 0,
    role: 'agent',
    account_id: 0,
    email: 'None',
  });

  /**
   * @type {import('vue').ComputedRef<Array>}
   */
  const assignableAgents = computed(() => {
    return inboxId.value
      ? assignable.value(inboxId.value, {
          includeAIAssignees,
        })
      : [];
  });

  const inboxBotAgent = computed(() =>
    getInboxBotAgent(assignableAgents.value)
  );

  const showNoneAgent = computed(
    () => includeNoneAgent && isAgentSelected.value && !inboxBotAgent.value
  );

  /**
   * @type {import('vue').ComputedRef<Array>}
   */
  const agentsList = computed(() => {
    const agents = assignableAgents.value || [];
    const humanAgents = agents.filter(
      agent => !isAIAssigneeType(agent.assignee_type)
    );
    const botAgents = agents.filter(agent =>
      isAIAssigneeType(agent.assignee_type)
    );
    const agentsByUpdatedPresence = getAgentsByUpdatedPresence(
      humanAgents,
      currentUser.value,
      currentAccountId.value
    );

    const filteredAgentsByAvailability = getSortedAgentsByAvailability(
      agentsByUpdatedPresence
    );

    return [
      ...(showNoneAgent.value ? [createNoneAgent()] : []),
      ...filteredAgentsByAvailability,
      ...botAgents,
    ];
  });

  return {
    agentsList,
    assignableAgents,
    inboxBotAgent,
  };
}
