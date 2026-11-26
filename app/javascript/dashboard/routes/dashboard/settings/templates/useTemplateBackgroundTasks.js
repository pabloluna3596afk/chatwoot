import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useBackgroundTasks } from 'dashboard/composables/useBackgroundTasks';

const ERRORS = ['REJECTED', 'DISABLED', 'PAUSED', 'FLAGGED'];
export const useTemplateBackgroundTasks = () => {
  const { t } = useI18n();
  const accountId = useMapGetter('getCurrentAccountId');
  const { track } = useBackgroundTasks();
  const register = submission => {
    if (
      submission.status === 'failed' ||
      submission.remote_status === 'APPROVED' ||
      ERRORS.includes(submission.remote_status)
    )
      return;
    track({
      id: `whatsapp_template_submission:${submission.id}`,
      kind: 'whatsapp_template',
      title: submission.name,
      status: 'running',
      detail:
        submission.status === 'submitted'
          ? t('BACKGROUND_TASKS.REVIEW')
          : t('BACKGROUND_TASKS.SENDING'),
      link: {
        label: t('BACKGROUND_TASKS.VIEW_TEMPLATE'),
        route: {
          name: 'settings_templates',
          params: { accountId: accountId.value },
          query: { q: submission.name },
        },
      },
    });
  };
  return { register };
};
