import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';

export const useLabelNavigation = () => {
  const router = useRouter();
  const accountId = useMapGetter('getCurrentAccountId');
  const goToLabel = title =>
    router.push({
      name: 'label_conversations',
      params: { accountId: accountId.value, label: title },
    });
  return { goToLabel };
};
