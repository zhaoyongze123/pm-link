import type { AuthPermissionInfo, Recordable, UserInfo } from '@vben/types';

import type { AuthApi } from '#/api';

import { ref } from 'vue';
import { useRouter } from 'vue-router';

import { LOGIN_PATH } from '@vben/constants';
import { preferences } from '@vben/preferences';
import { resetAllStores, useAccessStore, useUserStore } from '@vben/stores';

import { notification } from 'ant-design-vue';
import { defineStore } from 'pinia';

import {
  getAuthPermissionInfoApi,
  loginApi,
  logoutApi,
  register,
  smsLogin,
  socialLogin,
} from '#/api';
import { getUserProfile } from '#/api/system/user/profile';
import { $t } from '#/locales';
import { resolveUserHomePath } from '#/utils/oa-user';

const MENU_WHITELIST = new Set(['系统管理', '基础设施', '工作流程']);

function filterTopLevelMenus<T extends { children?: T[]; name?: string }>(
  menus: T[],
) {
  return menus.filter((menu) => MENU_WHITELIST.has(menu.name ?? ''));
}

export const useAuthStore = defineStore('auth', () => {
  const accessStore = useAccessStore();
  const userStore = useUserStore();
  const router = useRouter();

  const loginLoading = ref(false);

  /**
   * 异步处理登录操作
   * Asynchronously handle the login process
   * @param type 登录类型
   * @param params 登录表单数据
   * @param onSuccess 登录成功后的回调函数
   */
  async function authLogin(
    type: 'mobile' | 'register' | 'social' | 'username',
    params: Recordable<any>,
    onSuccess?: () => Promise<void> | void,
  ) {
    // 异步处理用户登录操作并获取 accessToken
    let userInfo: null | UserInfo = null;
    try {
      let loginResult: AuthApi.LoginResult;
      loginLoading.value = true;
      switch (type) {
        case 'mobile': {
          loginResult = await smsLogin(params as AuthApi.SmsLoginParams);
          break;
        }
        case 'register': {
          loginResult = await register(params as AuthApi.RegisterParams);
          break;
        }
        case 'social': {
          loginResult = await socialLogin(params as AuthApi.SocialLoginParams);
          break;
        }
        default: {
          loginResult = await loginApi(params);
        }
      }
      const { accessToken, refreshToken } = loginResult;

      // 如果成功获取到 accessToken
      if (accessToken) {
        accessStore.setAccessToken(accessToken);
        accessStore.setRefreshToken(refreshToken);

        // 获取用户信息并存储到 userStore、accessStore 中
        // TODO @芋艿：清理掉 accessCodes 相关的逻辑
        // const [fetchUserInfoResult, accessCodes] = await Promise.all([
        //   fetchUserInfo(),
        //   // getAccessCodesApi(),
        // ]);
        const fetchUserInfoResult = await fetchUserInfo();

        userInfo = fetchUserInfoResult.user;

        if (accessStore.loginExpired) {
          accessStore.setLoginExpired(false);
        } else {
          // oxlint-disable-next-line no-unused-expressions
          onSuccess
            ? await onSuccess?.()
            : await router.push(
                resolveUserHomePath(
                  preferences.app.defaultHomePath,
                  userInfo.homePath,
                  userStore.userRoles,
                ),
              );
        }

        if (userInfo?.nickname) {
          notification.success({
            description: `${$t('authentication.loginSuccessDesc')}:${userInfo?.nickname}`,
            duration: 3,
            message: $t('authentication.loginSuccess'),
          });
        }
      }
    } finally {
      loginLoading.value = false;
    }

    return {
      userInfo,
    };
  }

  async function logout(redirect: boolean = true) {
    try {
      const accessToken = accessStore.accessToken as string;
      if (accessToken) {
        await logoutApi(accessToken);
      }
    } catch {
      // 不做任何处理
    }
    resetAllStores();
    accessStore.setLoginExpired(false);

    // 回登录页带上当前路由地址
    await router.replace({
      path: LOGIN_PATH,
      query: redirect
        ? {
            redirect: encodeURIComponent(router.currentRoute.value.fullPath),
          }
        : {},
    });
  }

  async function fetchUserInfo() {
    // 加载
    // eslint-disable-next-line no-useless-assignment
    let authPermissionInfo: AuthPermissionInfo | null = null;
    const [permissionInfo, profile] = await Promise.all([
      getAuthPermissionInfoApi(),
      getUserProfile().catch(() => null),
    ]);
    authPermissionInfo = permissionInfo;
    const filteredMenus = filterTopLevelMenus(authPermissionInfo.menus || []);
    const userRoles = authPermissionInfo.roles || [];
    const normalizedUser = {
      ...authPermissionInfo.user,
      avatar: profile?.avatar || authPermissionInfo.user?.avatar || '',
      email: profile?.email ?? authPermissionInfo.user?.email,
      homePath: resolveUserHomePath(
        preferences.app.defaultHomePath,
        authPermissionInfo.user?.homePath,
        userRoles,
      ),
      nickname: profile?.nickname ?? authPermissionInfo.user?.nickname,
      username: profile?.username ?? authPermissionInfo.user?.username,
    };
    // userStore
    userStore.setUserInfo(normalizedUser);
    userStore.setUserRoles(userRoles);
    // accessStore
    accessStore.setAccessMenus(filteredMenus);
    accessStore.setAccessCodes(authPermissionInfo.permissions);
    return {
      ...authPermissionInfo,
      user: normalizedUser,
      menus: filteredMenus,
    };
  }

  function $reset() {
    loginLoading.value = false;
  }

  return {
    $reset,
    authLogin,
    fetchUserInfo,
    loginLoading,
    logout,
  };
});
