<script setup>
function getGoogleAuthUrl() {
  // Ideally a request to /auth/google_oauth2 should be made
  // Creating the URL manually because the devise-token-auth with
  // omniauth has a standing issue on redirecting the post request
  // https://github.com/lynndylanhurley/devise_token_auth/issues/1466
  const baseUrl = 'https://accounts.google.com/o/oauth2/auth';
  const clientId = window.chatwootConfig.googleOAuthClientId;
  const redirectUri = window.chatwootConfig.googleOAuthCallbackUrl;
  const responseType = 'code';
  const scope = 'email profile';

  // Build the query string
  const queryString = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: responseType,
    scope: scope,
  }).toString();

  // Construct the full URL
  return `${baseUrl}?${queryString}`;
}
</script>

<template>
  <div class="flex flex-col">
    <a
      :href="getGoogleAuthUrl()"
      class="relative flex h-14 w-full items-center justify-center rounded-full border border-n-weak bg-white px-12 text-center text-base font-medium text-n-slate-12 transition-colors hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand dark:border-n-slate-7 dark:text-n-black dark:hover:bg-n-slate-12"
    >
      <span
        class="i-logos-google-icon absolute start-5 size-5"
        aria-hidden="true"
      />
      <span>
        {{ $t('LOGIN.OAUTH.GOOGLE_LOGIN') }}
      </span>
    </a>
  </div>
</template>
