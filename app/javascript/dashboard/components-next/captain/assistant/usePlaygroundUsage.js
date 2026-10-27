import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

export const PLAYGROUND_MESSAGE_LIMIT = 500;

export const usePlaygroundUsage = () => {
  const { t } = useI18n();
  const remaining = ref(null);
  const errorCode = ref('');
  const retrySeconds = ref(0);
  const update = data => {
    if (data && 'test_usage' in data) remaining.value = data.test_usage;
    errorCode.value = '';
  };
  const handleError = error => {
    const data = error.response?.data;
    update(data);
    errorCode.value = data?.error_code || '';
    retrySeconds.value = Number(error.response?.headers?.['retry-after']) || 0;
    const errors = {
      responses_limit_reached: t(
        'CAPTAIN.PLAYGROUND.USAGE.responses_limit_reached'
      ),
      playground_rate_limit: t(
        'CAPTAIN.PLAYGROUND.USAGE.playground_rate_limit',
        { seconds: retrySeconds.value }
      ),
      playground_message_invalid: t(
        'CAPTAIN.PLAYGROUND.USAGE.playground_message_invalid'
      ),
      playground_history_invalid: t(
        'CAPTAIN.PLAYGROUND.USAGE.playground_history_invalid'
      ),
    };
    return errors[errorCode.value] || '';
  };
  const label = computed(() => {
    if (!remaining.value) return '';
    const usage = remaining.value;
    if (usage.uses_plan_pool && usage.plan_remaining <= 0) {
      return t('CAPTAIN.PLAYGROUND.USAGE.responses_limit_reached');
    }
    if (usage.daily_total === null) {
      return t('CAPTAIN.PLAYGROUND.USAGE.UNLIMITED_DAILY');
    }
    if (usage.plan_kind === 'free') {
      return t('CAPTAIN.PLAYGROUND.USAGE.FREE', {
        count: usage.plan_remaining,
      });
    }
    if (usage.daily_remaining > 0) {
      return t('CAPTAIN.PLAYGROUND.USAGE.DAILY', {
        used: usage.daily_used,
        total: usage.daily_total,
      });
    }
    return t('CAPTAIN.PLAYGROUND.USAGE.PLAN', {
      total: usage.daily_total,
      count: usage.plan_remaining,
    });
  });
  return { remaining, errorCode, label, update, handleError };
};
