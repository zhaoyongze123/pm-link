<script lang="ts" setup>
import { onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { AuthenticationAuthTitle } from '@vben/common-ui';
import { useAccessStore, useUserStore } from '@vben/stores';

import { message } from 'ant-design-vue';

import { kodSsoExchange } from '#/api/core/auth';
import { useAuthStore } from '#/store';
import { resolveKodEntryTarget } from '#/utils/kod-entry';

defineOptions({ name: 'KodSsoLogin' });

const KOD_SSO_CODE_STORAGE_PREFIX = 'kod-sso-consumed:';
let kodSsoLoginInFlight = false;

const route = useRoute();
const router = useRouter();
const authStore = useAuthStore();
const accessStore = useAccessStore();
const userStore = useUserStore();

const loading = ref(true);

function readQueryString(name: string) {
  const value = route.query[name];
  const normalizedValue = Array.isArray(value) ? value[0] : value;
  return typeof normalizedValue === 'string' ? normalizedValue : null;
}

function resolveTenantIdFromQuery() {
  const tenantIdText = readQueryString('tenantId');
  if (!tenantIdText) {
    return null;
  }
  const parsedTenantId = Number(tenantIdText);
  return Number.isFinite(parsedTenantId) && parsedTenantId > 0
    ? parsedTenantId
    : null;
}

function resolveEntryPath() {
  return resolveKodEntryTarget(
    route.query,
    userStore.userInfo?.homePath,
    userStore.userRoles,
  );
}

function buildLoginFallbackTarget() {
  return encodeURIComponent(resolveEntryPath());
}

function resolveKodSsoCode() {
  const value = route.query.kodSsoCode;
  const normalizedValue = Array.isArray(value) ? value[0] : value;
  return typeof normalizedValue === 'string' ? normalizedValue : null;
}

function buildConsumedCodeKey(code: string) {
  return `${KOD_SSO_CODE_STORAGE_PREFIX}${code}`;
}

function markCodeConsumed(code: string) {
  sessionStorage.setItem(buildConsumedCodeKey(code), '1');
}

function isCodeConsumed(code: string) {
  return sessionStorage.getItem(buildConsumedCodeKey(code)) === '1';
}

async function clearKodSsoCodeFromUrl() {
  if (!('kodSsoCode' in route.query)) {
    return;
  }
  const nextQuery = { ...route.query };
  delete nextQuery.kodSsoCode;
  await router.replace({
    path: route.path,
    query: nextQuery,
  });
}

async function handleKodSsoLogin() {
  if (kodSsoLoginInFlight) {
    return;
  }
  const tenantId = resolveTenantIdFromQuery();
  if (tenantId) {
    accessStore.setTenantId(tenantId);
  }

  const code = resolveKodSsoCode();
  if (!code) {
    if (accessStore.accessToken && !userStore.userInfo) {
      await authStore.fetchUserInfo();
    }
    await router.replace(resolveEntryPath());
    return;
  }
  if (!tenantId && !accessStore.tenantId) {
    throw new Error('缺少租户编号，无法完成可道云登录');
  }

  if (isCodeConsumed(code)) {
    await router.replace(resolveEntryPath());
    return;
  }

  kodSsoLoginInFlight = true;
  try {
    markCodeConsumed(code);
    await clearKodSsoCodeFromUrl();

    const loginResult = await kodSsoExchange(code);
    accessStore.setAccessToken(loginResult.accessToken);
    accessStore.setRefreshToken(loginResult.refreshToken);

    await authStore.fetchUserInfo();
    const targetPath = resolveEntryPath();

    await router.replace(targetPath);
  } catch (error) {
    sessionStorage.removeItem(buildConsumedCodeKey(code));
    throw error;
  } finally {
    kodSsoLoginInFlight = false;
  }
}

onMounted(async () => {
  try {
    await handleKodSsoLogin();
  } catch (error: any) {
    const isConsumedCodeError =
      error?.message === '可道云登录换票码不存在或已过期';
    if (!isConsumedCodeError) {
      message.error(error?.message || '可道云登录失败');
    }
    await router.replace({
      path: '/auth/login',
      query: {
        redirect: buildLoginFallbackTarget(),
      },
    });
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="kod-sso-loading-shell">
    <div class="kod-sso-loading-card">
      <div class="kod-sso-loading-brand" aria-hidden="true"></div>
      <AuthenticationAuthTitle>
        <template #title>可道云登录中</template>
        <template #desc>
          <span class="kod-sso-loading-desc">正在同步账号权限并恢复当前页面，请稍候</span>
        </template>
      </AuthenticationAuthTitle>
      <div v-if="loading" class="kod-sso-loading-progress" aria-hidden="true"></div>
      <div v-if="loading" class="kod-sso-loading-dots" aria-hidden="true">
        <span></span>
        <span></span>
        <span></span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.kod-sso-loading-shell {
  display: flex;
  min-height: max(420px, calc(100vh - 140px));
  align-items: center;
  justify-content: center;
  padding: 24px;
  background:
    radial-gradient(circle at 14% 18%, rgb(37 99 235 / 10%), transparent 24%),
    radial-gradient(circle at 84% 10%, rgb(14 165 233 / 10%), transparent 22%),
    linear-gradient(180deg, #f6f9fd 0%, #edf3f9 100%);
}

.kod-sso-loading-card {
  display: grid;
  width: min(460px, 100%);
  gap: 16px;
  padding: 30px 26px 24px;
  border: 1px solid rgb(219 228 238 / 96%);
  border-radius: 24px;
  background: rgb(255 255 255 / 84%);
  box-shadow:
    0 22px 48px rgb(15 23 42 / 8%),
    inset 0 1px 0 rgb(255 255 255 / 68%);
  backdrop-filter: blur(12px);
}

.kod-sso-loading-brand {
  display: flex;
  height: 44px;
  width: 44px;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%);
  box-shadow: inset 0 1px 0 rgb(255 255 255 / 80%);
}

.kod-sso-loading-brand::before {
  content: '';
  width: 16px;
  height: 16px;
  border: 2px solid rgb(37 99 235 / 18%);
  border-top-color: #2563eb;
  border-radius: 999px;
  animation: kod-sso-loading-spin 0.9s linear infinite;
}

.kod-sso-loading-desc {
  color: #4c5b70;
  font-size: 13px;
  line-height: 1.7;
}

.kod-sso-loading-progress {
  position: relative;
  height: 4px;
  overflow: hidden;
  border-radius: 999px;
  background: rgb(203 213 225 / 72%);
}

.kod-sso-loading-progress::before {
  content: '';
  position: absolute;
  inset: 0;
  width: 34%;
  border-radius: inherit;
  background: linear-gradient(90deg, #2563eb 0%, #0ea5e9 100%);
  animation: kod-sso-loading-slide 1.15s ease-in-out infinite;
}

.kod-sso-loading-dots {
  display: flex;
  gap: 8px;
}

.kod-sso-loading-dots span {
  width: 6px;
  height: 6px;
  border-radius: 999px;
  background: rgb(59 130 246 / 32%);
  animation: kod-sso-loading-bounce 1.1s ease-in-out infinite;
}

.kod-sso-loading-dots span:nth-child(2) {
  animation-delay: 0.16s;
}

.kod-sso-loading-dots span:nth-child(3) {
  animation-delay: 0.32s;
}

@keyframes kod-sso-loading-slide {
  0% {
    transform: translateX(-120%);
  }

  60%,
  100% {
    transform: translateX(220%);
  }
}

@keyframes kod-sso-loading-bounce {
  0%,
  100% {
    opacity: 0.38;
    transform: translateY(0);
  }

  50% {
    opacity: 1;
    transform: translateY(-3px);
  }
}

@keyframes kod-sso-loading-spin {
  0% {
    transform: rotate(0deg);
  }

  100% {
    transform: rotate(360deg);
  }
}

@media (max-width: 640px) {
  .kod-sso-loading-shell {
    min-height: max(360px, calc(100vh - 96px));
    padding: 16px;
  }

  .kod-sso-loading-card {
    padding: 24px 18px 20px;
    border-radius: 20px;
  }
}
</style>
