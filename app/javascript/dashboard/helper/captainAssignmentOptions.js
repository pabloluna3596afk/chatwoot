import { isAIAssigneeType } from './assigneeHelper';

export const buildCaptainOptions = ({
  inboxIds = [],
  inboxes = [],
  assistants = [],
  t,
}) => {
  const general = {
    id: 'captain',
    name: t('CAPTAIN.ASSIGNMENT.GENERAL'),
    icon: 'i-woot-captain',
  };
  if (!inboxIds.length) return [general];
  const pinned = inboxes.filter(inbox => inboxIds.includes(inbox.id));
  const ids = [
    ...new Set(
      pinned.flatMap(inbox =>
        inbox.captain_assistant ? [inbox.captain_assistant.id] : []
      )
    ),
  ];
  const options = ids.map(id => ({
    id: `captain:${id}`,
    name:
      assistants.find(assistant => assistant.id === id)?.name ||
      pinned.find(inbox => inbox.captain_assistant?.id === id).captain_assistant
        .name,
    icon: 'i-woot-captain',
  }));
  if (pinned.some(inbox => !inbox.captain_assistant)) {
    options.push({
      ...general,
      description: t('CAPTAIN.ASSIGNMENT.NO_ASSISTANT'),
    });
  }
  return options;
};

export const withAIAssigneesFirst = list => [
  ...list.filter(agent => agent.assignee_type === 'Captain::Assistant'),
  ...list.filter(agent => agent.assignee_type === 'AgentBot'),
  ...list.filter(agent => !isAIAssigneeType(agent.assignee_type)),
];
