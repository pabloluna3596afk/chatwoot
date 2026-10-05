<script setup>
import { useI18n } from 'vue-i18n';
import FlowBuilderPage from './FlowBuilderPage.vue';

// The story shows the page in Spanish, as the owner sees it.
useI18n().locale.value = 'es';

const flow = {
  id: null,
  name: 'Datos del cliente',
  categories: ['LEAD_GENERATION'],
  definition: {
    schema_version: 1,
    screens: [
      {
        title: 'Tus datos',
        button: 'Continuar',
        blocks: [
          {
            type: 'short_text',
            key: 'nombre',
            label: 'Nombre completo',
            required: true,
            input: 'text',
          },
          {
            type: 'short_text',
            key: 'correo',
            label: 'Correo electrónico',
            required: true,
            input: 'email',
          },
          {
            type: 'short_text',
            key: 'cedula',
            label: 'Cédula',
            required: true,
            input: 'text',
          },
        ],
      },
      {
        title: 'Tu cita',
        button: 'Enviar',
        blocks: [
          {
            type: 'radio',
            key: 'necesitas',
            label: '¿Qué necesitas?',
            required: true,
            options: [
              { id: 'consulta', title: 'Consulta' },
              { id: 'seguimiento', title: 'Seguimiento' },
              { id: 'otro', title: 'Otro' },
            ],
          },
          {
            type: 'long_text',
            key: 'cuentanos_mas',
            label: 'Cuéntanos más',
            required: false,
            visible_when: { key: 'necesitas', op: 'equals', value: 'otro' },
          },
          {
            type: 'optin',
            key: 'acepto',
            label: 'Acepto la política de privacidad',
            required: true,
          },
        ],
      },
    ],
  },
};

// No server in the story: the check says everything is fine and "saving" only answers.
const api = {
  validate: async () => ({
    data: { errors: [], flow_json: { version: '7.1' } },
  }),
  create: async payload => ({ data: { id: 1, ...payload } }),
  update: async (id, payload) => ({ data: { id, ...payload } }),
};
</script>

<template>
  <Story title="Flows/Builder page" :layout="{ type: 'single' }">
    <!-- Resize the preview (or the window): below 960px the columns stack. -->
    <Variant title="Full page">
      <div class="p-4 bg-n-surface-1">
        <FlowBuilderPage :flow="flow" :api="api" />
      </div>
    </Variant>
  </Story>
</template>
