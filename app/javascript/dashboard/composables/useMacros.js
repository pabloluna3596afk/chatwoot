import { formatMacroPreviewValue } from 'dashboard/helper/shortcutPreview';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { PRIORITY_CONDITION_VALUES } from 'dashboard/constants/automation';
import { useCaptainAssignment } from './useCaptainAssignment';
import {
  isCaptainSelection,
  captainSelection,
} from 'dashboard/helper/captainAssignment';
import {
  generateLabelOptions,
  generateTeamOptions,
} from 'dashboard/helper/automationHelper';
import {
  resolveActionName,
  getFileName,
} from 'dashboard/routes/dashboard/settings/macros/macroHelper';

/**
 * Composable for handling macro-related functionality
 * @returns {Object} An object containing the getMacroDropdownValues and resolveMacroActions functions
 */
export const useMacros = () => {
  const { t } = useI18n();
  const { options: captainOptions } = useCaptainAssignment();
  const getters = useStoreGetters();

  const labels = computed(() => getters['labels/getLabels'].value);
  const teams = computed(() => getters['teams/getTeams'].value);
  const agents = computed(() => getters['agents/getVerifiedAgents'].value);

  const withNoneOption = options => [
    { id: 'nil', name: t('AUTOMATION.NONE_OPTION') },
    ...(options || []),
  ];

  /**
   * Get dropdown values based on the specified type
   * @param {string} type - The type of dropdown values to retrieve
   * @returns {Array} An array of dropdown values
   */
  const getMacroDropdownValues = type => {
    switch (type) {
      case 'assign_team':
        return withNoneOption(generateTeamOptions(teams.value));
      case 'assign_agent':
        return [
          ...captainOptions.value,
          ...withNoneOption(),
          { id: 'self', name: 'Self' },
          ...agents.value,
        ];
      case 'add_label':
      case 'remove_label':
        return generateLabelOptions(labels.value);
      case 'change_priority':
        return PRIORITY_CONDITION_VALUES.map(item => ({
          id: item.id,
          name: t(`MACROS.PRIORITY_TYPES.${item.i18nKey}`),
        }));
      default:
        return [];
    }
  };

  const resolveActionValue = (
    { action_name: name, action_params: params },
    files,
    variables
  ) => {
    if (!variables && !params?.length) return '';
    if (!params) return '';
    if (!Array.isArray(params)) return params;
    if (!params.length) return '';

    if (variables && name === 'change_status') {
      return t(`CONVERSATION.PICKER.PREVIEW.STATUS.${params[0]}`);
    }
    const options = getMacroDropdownValues(name);
    if (options.length) {
      return params
        .map(id => {
          if (variables && name === 'assign_agent' && id === 'self') {
            return (
              variables['agent.name'] || t('CONVERSATION.PICKER.PREVIEW.SELF')
            );
          }
          if (isCaptainSelection(id))
            return captainSelection(id, options, t).name;
          const label = options.find(
            option => String(option.id) === String(id)
          )?.name;
          return (
            label || (variables ? t('CONVERSATION.PICKER.PREVIEW.MISSING') : '')
          );
        })
        .filter(Boolean)
        .join(', ');
    }

    if (name === 'send_attachment') return getFileName(params[0], name, files);

    return variables && params.length > 1 ? params : params[0];
  };

  /**
   * Resolve a macro into the action name and value pairs shown in its preview.
   * Actions that store option ids are looked up in the same dropdown values the
   * macro builder offers, so the preview never drifts from what can be built.
   * @param {Object} macro - The macro to resolve
   * @returns {Array} An array of { actionName, actionValue } pairs
   */
  const resolveMacroActions = (macro, variables) =>
    macro.actions.map(action => ({
      actionName: resolveActionName(action.action_name),
      actionValue: variables
        ? formatMacroPreviewValue(
            resolveActionValue(action, macro.files, variables),
            variables,
            t
          )
        : resolveActionValue(action, macro.files),
    }));

  return {
    getMacroDropdownValues,
    resolveMacroActions,
  };
};
