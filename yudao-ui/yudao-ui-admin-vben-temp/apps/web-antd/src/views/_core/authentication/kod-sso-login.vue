<script lang="ts" setup>
import { onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { AuthenticationAuthTitle } from '@vben/common-ui';
import { preferences } from '@vben/preferences';
import { useAccessStore, useUserStore } from '@vben/stores';

import { message, Spin } from 'ant-design-vue';

import { kodSsoExchange } from '#/api/core/auth';
import { useAuthStore } from '#/store';
import { resolveUserHomePath } from '#/utils/oa-user';

defineOptions({ name: 'KodSsoLogin' });

const route = useRoute();
const router = useRouter();
const authStore = useAuthStore();
const accessStore = useAccessStore();
const userStore = useUserStore();

const loading = ref(true);

function resolveTenantIdFromQuery() {
  const tenantId = route.query.tenantId;
  const tenantIdText = Array.isArray(tenantId) ? tenantId[0] : tenantId;
  if (!tenantIdText) {
    return null;
  }
  const parsedTenantId = Number(tenantIdText);
  return Number.isFinite(parsedTenantId) && parsedTenantId > 0
    ? parsedTenantId
    : null;
}

async function handleKodSsoLogin() {
  const tenantId = resolveTenantIdFromQuery();
  if (tenantId) {
    accessStore.setTenantId(tenantId);
  }

  const kodSsoCode = route.query.kodSsoCode;
  const code = Array.isArray(kodSsoCode) ? kodSsoCode[0] : kodSsoCode;
  if (!code) {
    throw new Error('缺少可道云登录换票码');
  }
  if (!tenantId && !accessStore.tenantId) {
    throw new Error('缺少租户编号，无法完成可道云登录');
  }

  const loginResult = await kodSsoExchange(code);
  accessStore.setAccessToken(loginResult.accessToken);
  accessStore.setRefreshToken(loginResult.refreshToken);

  const authPermissionInfo = await authStore.fetchUserInfo();
  const targetPath = resolveUserHomePath(
    preferences.app.defaultHomePath,
    authPermissionInfo.user?.homePath,
    userStore.userRoles,
  );

  await router.replace(targetPath);
}

onMounted(async () => {
  try {
    await handleKodSsoLogin();
  } catch (error: any) {
    message.error(error?.message || '可道云登录失败');
    await router.replace('/auth/login');
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex min-h-[360px] flex-col items-center justify-center gap-6">
    <AuthenticationAuthTitle>
      <template #title>可道云登录中</template>
      <template #desc>
        <span class="text-muted-foreground">正在同步账号与权限，请稍候...</span>
      </template>
    </AuthenticationAuthTitle>
    <Spin :spinning="loading" size="large" />
  </div>
</template>
