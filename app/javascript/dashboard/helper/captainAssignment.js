export const isCaptainSelection = value =>
  typeof value === 'string' && /^captain(?::[1-9]\d*)?$/.test(value);

export const captainSelection = (id, options, t) =>
  options.find(option => option.id === id) || {
    id,
    name:
      id === 'captain'
        ? t('CAPTAIN.ASSIGNMENT.GENERAL')
        : t('CAPTAIN.ASSIGNMENT.DELETED'),
  };

export const captainInboxOptions = (inboxes, assistantId, t) =>
  inboxes.map(inbox => {
    const other =
      inbox.captain_assistant && inbox.captain_assistant.id !== assistantId;
    return {
      value: inbox.id,
      label: other
        ? `${inbox.name} — ${t('CAPTAIN.ASSIGNMENT.CONNECTED_TO', { name: inbox.captain_assistant.name })}`
        : inbox.name,
      disabled: Boolean(other),
    };
  });

const pinnedInboxIds = conditions =>
  conditions
    .filter(
      c => c.attribute_key === 'inbox_id' && c.filter_operator === 'equal_to'
    )
    .flatMap(c => [c.values].flat().map(value => value?.id ?? value));

const captainSelections = actions =>
  actions
    .filter(action => action.action_name === 'assign_agent')
    .flatMap(action =>
      [action.action_params].flat().map(value => value?.id ?? value)
    )
    .filter(isCaptainSelection);

const selectionFits = (selection, assistant) =>
  Boolean(assistant) &&
  (selection === 'captain' || selection === `captain:${assistant.id}`);

// One line per Inbox pinned by the rule: who will be assigned there, or why nobody will.
export const captainAssignmentSummary = (conditions, actions, inboxes) => {
  const [selection] = captainSelections(actions);
  if (!selection) return [];
  const ids = pinnedInboxIds(conditions);
  return inboxes
    .filter(inbox => ids.includes(inbox.id))
    .map(inbox => {
      const assistant = inbox.captain_assistant || null;
      let status = 'ok';
      if (!assistant) status = 'none';
      else if (!selectionFits(selection, assistant)) status = 'different';
      return { inbox, assistant, status };
    });
};

export const hasCaptainSelection = actions =>
  captainSelections(actions).length > 0;

export const unsupportedCaptainInboxes = (conditions, actions, inboxes) =>
  captainAssignmentSummary(conditions, actions, inboxes)
    .filter(line => line.status !== 'ok')
    .map(line => line.inbox);
