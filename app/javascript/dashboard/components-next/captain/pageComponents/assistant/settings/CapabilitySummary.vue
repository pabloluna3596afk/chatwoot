<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import CapabilityRow from './CapabilityRow.vue';

const props = defineProps({
  assistant: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['focusTemplatesToggle']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const capabilities = ref(props.assistant?.capabilities || null);
const groups = computed(() => capabilities.value?.groups || []);
const readyCount = computed(() =>
  groups.value.reduce(
    (total, group) =>
      total + group.items.filter(item => item.status === 'ready').length,
    0
  )
);
const hasNoConnections = computed(() =>
  ['whatsapp', 'calendar'].every(
    id =>
      groups.value.find(group => group.id === id)?.connection ===
      'not_connected'
  )
);
const connectWhatsApp = () => {
  const group = groups.value.find(item => item.id === 'whatsapp');
  if (!group?.connect_route) return;
  router.push({
    name: group.connect_route,
    params: {
      accountId: route.params.accountId,
      assistantId: route.params.assistantId,
    },
  });
};

watch(
  () => props.assistant?.capabilities,
  value => {
    if (value) capabilities.value = value;
  }
);

onMounted(async () => {
  if (capabilities.value || !route.params.assistantId) return;
  try {
    const assistant = await store.dispatch(
      'captainAssistants/show',
      route.params.assistantId
    );
    capabilities.value = assistant?.capabilities || null;
  } catch {
    capabilities.value = null;
  }
});

const focusTemplatesToggle = () => emit('focusTemplatesToggle');
</script>

<template>
  <template v-if="capabilities">
    <section
      class="flex flex-col"
      data-testid="capability-summary"
      aria-labelledby="capability-summary-title"
    >
      <div class="flex flex-wrap items-baseline justify-between gap-1">
        <h3
          id="capability-summary-title"
          class="mb-0 text-heading-3 text-n-slate-12"
        >
          {{ t('CAPTAIN.ASSISTANTS.CAPABILITIES.TITLE') }}
        </h3>
        <span
          class="text-body-main text-n-slate-11 tabular-nums"
          aria-live="polite"
        >
          {{
            t('CAPTAIN.ASSISTANTS.CAPABILITIES.COUNT', {
              ready: readyCount,
              total: 6,
            })
          }}
        </span>
      </div>
      <p class="mt-1 mb-0 text-xs text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.CAPABILITIES.SAVED_NOTE') }}
      </p>

      <div
        v-if="hasNoConnections"
        class="flex flex-wrap items-center justify-between gap-3 p-4 mt-3 rounded-xl bg-n-alpha-1"
        data-testid="capabilities-nothing-connected"
      >
        <p
          class="flex flex-col flex-1 min-w-0 gap-1 mb-0 text-sm text-n-slate-12"
        >
          <span>{{
            t('CAPTAIN.ASSISTANTS.CAPABILITIES.NOTHING_CONNECTED.TITLE')
          }}</span>
          <span class="text-n-slate-11">
            {{ t('CAPTAIN.ASSISTANTS.CAPABILITIES.NOTHING_CONNECTED.BODY') }}
          </span>
        </p>
        <Button
          :label="t('CAPTAIN.ASSISTANTS.CAPABILITIES.NOTHING_CONNECTED.ACTION')"
          data-testid="capabilities-connect-whatsapp"
          @click="connectWhatsApp"
        />
      </div>

      <div
        v-for="group in groups"
        :key="group.id"
        class="mt-4"
        data-testid="capability-group"
      >
        <div class="flex flex-wrap items-center gap-2 mb-2">
          <h4 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t(`CAPTAIN.ASSISTANTS.CAPABILITIES.GROUPS.${group.id}`) }}
          </h4>
          <Label
            :label="
              t(
                `CAPTAIN.ASSISTANTS.CAPABILITIES.CONNECTION.${group.connection}`
              )
            "
            :color="
              {
                connected: 'teal',
                needs_review: 'amber',
                not_connected: 'blue',
              }[group.connection] || 'slate'
            "
            compact
          >
            <template v-if="group.connection !== 'always'" #icon>
              <Icon
                :icon="
                  {
                    connected: 'i-lucide-circle-check',
                    needs_review: 'i-lucide-wrench',
                    not_connected: 'i-lucide-plug',
                  }[group.connection]
                "
                class="size-3.5"
                aria-hidden="true"
              />
            </template>
          </Label>
        </div>
        <ul
          class="p-0 m-0 overflow-hidden list-none rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
          :aria-label="t(`CAPTAIN.ASSISTANTS.CAPABILITIES.GROUPS.${group.id}`)"
        >
          <CapabilityRow
            v-for="(item, index) in group.items"
            :key="item.id"
            :item="item"
            :group="group"
            :class="{ 'border-t border-n-weak': index > 0 }"
            @focus-templates-toggle="focusTemplatesToggle"
          />
        </ul>
      </div>
    </section>
  </template>
</template>
