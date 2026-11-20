<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  entry: { type: Object, default: undefined },
  mobile: { type: Boolean, default: false },
});
defineEmits(['retry', 'close']);
const { t } = useI18n();
const key = 'CONVERSATION.CAPTAIN_DECISION';
const decisions = computed(() => props.entry?.decisions || []);
const loading = computed(() => !props.entry || props.entry.loading);
const technicalValue = value =>
  value.status === 'recorded'
    ? value.value
    : t(
        `${key}.${value.status === 'not_applicable' ? 'NOT_APPLICABLE' : 'NOT_RECORDED'}`
      );
const sources = decision => [
  ...(decision.evidence?.sources?.documents || []),
  ...(decision.evidence?.sources?.faqs || []),
];
const sourceGroups = decision =>
  [
    {
      label: 'SOURCES_USED',
      items: sources(decision).filter(source =>
        ['used', 'cited'].includes(source.usage)
      ),
    },
    {
      label: 'SOURCES_CONSULTED',
      items: sources(decision).filter(source => source.usage === 'consulted'),
    },
  ].filter(group => group.items.length);
const facts = decision => {
  const evidence = decision.evidence || {};
  const flags = [
    'complete',
    'customerConfirmed',
    'expectsCustomerReply',
    'probableComplete',
  ]
    .filter(field => typeof evidence[field] === 'boolean')
    .map(field => t(`${key}.FACTS.${field}.${evidence[field]}`));
  const enums = ['action', 'cancellationCause', 'error']
    .filter(field => evidence[field])
    .map(field => t(`${key}.FACTS.${field}.${evidence[field]}`));
  if (evidence.reasonCategory) {
    enums.push(
      t(`CONVERSATION.CAPTAIN_HANDOFF.REASON.${evidence.reasonCategory}`)
    );
  }
  return [...flags, ...enums];
};
const isEvaluation = decision =>
  decision.origin === 'model' &&
  (decision.trigger === 'evaluation' ||
    decision.kind === 'completion_review' ||
    (decision.trigger === 'inactivity' &&
      ['resolve', 'handoff'].includes(decision.kind)));
const technicalRows = decision =>
  Object.entries(decision.technical || {})
    .filter(([field]) => ['model', 'creditsConsumed', 'cost'].includes(field))
    .map(([field, value]) => ({
      field,
      text: t(`${key}.TECHNICAL.${field}`, { value: technicalValue(value) }),
    }));
const outcomeClass = outcome => {
  if (['created', 'completed', 'confirmed'].includes(outcome)) {
    return 'bg-n-teal-3 text-n-teal-11';
  }
  if (outcome === 'pending') return 'bg-n-amber-3 text-n-amber-12';
  if (['failed', 'rejected', 'cancelled'].includes(outcome)) {
    return 'bg-n-ruby-3 text-n-ruby-11';
  }
  return 'bg-n-alpha-2 text-n-slate-11';
};
const settingRows = decision =>
  Object.entries(decision.evidence?.settings || {});
</script>

<template>
  <section
    :role="mobile ? undefined : 'dialog'"
    :aria-label="t('CONVERSATION.CAPTAIN_DECISION.TITLE')"
    :aria-busy="loading"
    class="w-full md:w-96 max-w-full overflow-hidden rounded-[14px] border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 shadow-xl [overflow-wrap:anywhere]"
  >
    <header
      class="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-n-weak bg-n-solid-1 px-4 py-2.5"
    >
      <div class="flex flex-wrap items-center gap-2">
        <h2 class="m-0 text-sm font-semibold">
          {{ t('CONVERSATION.CAPTAIN_DECISION.TITLE') }}
        </h2>
        <span
          v-if="!loading && !entry?.error && decisions.length === 1"
          class="inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium"
          :class="outcomeClass(decisions[0].outcome)"
        >
          <span class="sr-only">{{
            t('CONVERSATION.CAPTAIN_DECISION.OUTCOME')
          }}</span>
          {{ t(`${key}.OUTCOMES.${decisions[0].outcome}`) }}
        </span>
      </div>
      <button
        type="button"
        class="flex size-11 md:size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
        :aria-label="t('CONVERSATION.CAPTAIN_DECISION.CLOSE')"
        @click="$emit('close')"
      >
        <Icon icon="i-lucide-x" class="size-4" aria-hidden="true" />
      </button>
    </header>
    <div class="flex flex-col gap-3.5 p-4">
      <p v-if="loading" role="status" class="m-0">
        {{ t('CONVERSATION.CAPTAIN_DECISION.LOADING') }}
      </p>
      <div v-else-if="entry.error" class="flex flex-col items-start gap-3">
        <p role="alert" class="m-0">
          {{
            t(`${key}.${entry.error === 'forbidden' ? 'FORBIDDEN' : 'ERROR'}`)
          }}
        </p>
        <Button
          v-if="entry.error !== 'forbidden'"
          intent="secondary"
          :label="t('CONVERSATION.CAPTAIN_DECISION.RETRY')"
          @click="$emit('retry')"
        />
      </div>
      <p v-else-if="!decisions.length" class="m-0">
        {{ t('CONVERSATION.CAPTAIN_DECISION.EMPTY') }}
      </p>
      <article
        v-for="decision in loading || entry?.error ? [] : decisions"
        :key="decision.id"
        class="flex flex-col gap-3"
      >
        <div v-if="decisions.length > 1" class="flex items-center gap-2">
          <span class="sr-only">{{
            t('CONVERSATION.CAPTAIN_DECISION.OUTCOME')
          }}</span
          ><span
            class="inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium"
            :class="outcomeClass(decision.outcome)"
            >{{ t(`${key}.OUTCOMES.${decision.outcome}`) }}</span
          >
        </div>
        <div>
          <h3
            class="mb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('CONVERSATION.CAPTAIN_DECISION.WHY') }}
          </h3>
          <p class="m-0 rounded-lg bg-n-solid-2 px-3 py-2">
            {{
              decision.reasonText ||
              t('CONVERSATION.CAPTAIN_DECISION.NO_REASON')
            }}
          </p>
        </div>
        <div>
          <h3
            class="mb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('CONVERSATION.CAPTAIN_DECISION.EVIDENCE') }}
          </h3>
          <p v-if="!facts(decision).length" class="m-0">
            {{
              t(
                decision.kind === 'reply' &&
                  !sources(decision).length &&
                  !decision.evidence?.tools?.length
                  ? 'CONVERSATION.CAPTAIN_DECISION.NO_SOURCES_OR_TOOLS'
                  : 'CONVERSATION.CAPTAIN_DECISION.NO_EVIDENCE'
              )
            }}
          </p>
          <ul v-if="facts(decision).length" class="m-0 ps-4 list-disc">
            <li v-for="fact in facts(decision)" :key="fact">{{ fact }}</li>
          </ul>
        </div>
        <div v-for="group in sourceGroups(decision)" :key="group.label">
          <h3
            class="mb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t(`${key}.${group.label}`) }}
          </h3>
          <ul class="m-0 ps-4 list-disc">
            <li
              v-for="source in group.items"
              :key="`${source.id}-${source.title}`"
            >
              <a
                v-if="source.link"
                :href="source.link"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-blue-11 underline"
                >{{ source.title }}</a
              ><span v-else>{{
                source.title ||
                t('CONVERSATION.CAPTAIN_DECISION.SOURCE_UNAVAILABLE')
              }}</span>
            </li>
          </ul>
        </div>
        <div v-if="decision.evidence?.tools?.length">
          <h3
            class="mb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('CONVERSATION.CAPTAIN_DECISION.ACTIONS') }}
          </h3>
          <ul class="m-0 ps-4 list-disc">
            <li v-for="tool in decision.evidence.tools" :key="tool">
              {{
                t('CONVERSATION.CAPTAIN_DECISION.TOOL_CALLED', {
                  name: tool.replaceAll('_', ' '),
                })
              }}
            </li>
          </ul>
        </div>
        <div>
          <h3
            class="mb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('CONVERSATION.CAPTAIN_DECISION.AFTERWARDS') }}
          </h3>
          <ul
            v-if="decision.afterwards?.status === 'recorded'"
            class="m-0 ps-4 list-disc"
          >
            <li v-for="(fact, index) in decision.afterwards.facts" :key="index">
              {{ t(`${key}.LATER.${fact.type}`) }}
            </li>
          </ul>
          <p v-else class="m-0">
            {{ t('CONVERSATION.CAPTAIN_DECISION.NO_LATER_EVENTS') }}
          </p>
        </div>
        <dl
          class="m-0 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 rounded-lg bg-n-solid-2 px-3 py-2 text-[13px]"
        >
          <dt class="text-n-slate-11">
            {{ t('CONVERSATION.CAPTAIN_DECISION.ORIGIN') }}
          </dt>
          <dd class="m-0">{{ t(`${key}.ORIGINS.${decision.origin}`) }}</dd>
          <template
            v-for="[setting, value] in settingRows(decision)"
            :key="setting"
          >
            <dt class="text-n-slate-11">{{ t(`${key}.RULE`) }}</dt>
            <dd class="m-0">
              {{ t(`${key}.SETTINGS.${setting}`, { minutes: value }) }}
            </dd>
          </template>
        </dl>
        <RouterLink
          v-if="decision.canChangeSetting"
          :to="decision.settingDestination"
          class="inline-flex min-h-8 items-center text-n-blue-11 underline underline-offset-2"
          @click="$emit('close')"
        >
          {{ t('CONVERSATION.CAPTAIN_DECISION.CHANGE_SETTING') }}
        </RouterLink>
        <p
          v-if="decision.kind === 'close_unanswered'"
          class="m-0 rounded-lg border border-n-amber-6 bg-n-amber-3 p-2.5 text-xs text-n-amber-12"
        >
          {{ t('CONVERSATION.CAPTAIN_DECISION.SILENCE_WARNING') }}
        </p>
        <p
          v-if="isEvaluation(decision)"
          class="m-0 rounded-lg border border-n-amber-6 bg-n-amber-3 p-2.5 text-xs text-n-amber-12"
        >
          {{ t('CONVERSATION.CAPTAIN_DECISION.EVALUATION_COST_NOTICE') }}
        </p>
        <footer
          v-if="technicalRows(decision).length"
          class="border-t border-dashed border-n-weak pt-2 font-mono text-xs text-n-slate-11"
        >
          <p
            v-for="row in technicalRows(decision)"
            :key="row.field"
            class="m-0"
          >
            {{ row.text }}
          </p>
        </footer>
      </article>
    </div>
  </section>
</template>
