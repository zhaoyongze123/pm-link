import type { AppRouteRecordRaw, MenuRecordRaw } from '@vben/types';
import type { RouteRecordRaw } from 'vue-router';

const REMOVED_MENU_PATH_PREFIXES = ['/system/dict'];
const REMOVED_MENU_NAMES = new Set(['字典管理']);

function isRemovedMenuPath(path?: string) {
  if (!path) {
    return false;
  }
  return REMOVED_MENU_PATH_PREFIXES.some(
    (prefix) => path === prefix || path.startsWith(`${prefix}/`),
  );
}

function isRemovedMenuName(name?: string) {
  return !!name && REMOVED_MENU_NAMES.has(name);
}

function shouldRemoveEntry(entry?: { name?: string; path?: string }) {
  return isRemovedMenuName(entry?.name) || isRemovedMenuPath(entry?.path);
}

function filterMenuTree<T extends { children?: T[]; name?: string; path?: string }>(
  menus: T[] = [],
): T[] {
  return menus.reduce<T[]>((result, menu) => {
    if (shouldRemoveEntry(menu)) {
      return result;
    }
    const filteredChildren = menu.children
      ? filterMenuTree(menu.children)
      : undefined;
    result.push({
      ...menu,
      children: filteredChildren,
    });
    return result;
  }, []);
}

function filterAccessMenus(menus: AppRouteRecordRaw[] = []) {
  return filterMenuTree<AppRouteRecordRaw>(menus);
}

function filterMenuRecords(menus: MenuRecordRaw[] = []) {
  return filterMenuTree<MenuRecordRaw>(menus);
}

function filterAccessRoutes(routes: RouteRecordRaw[] = []) {
  return routes.filter((route) => !isRemovedMenuPath(route.path));
}

function isBlockedMenuPath(path: string) {
  return isRemovedMenuPath(path);
}

export {
  filterAccessMenus,
  filterAccessRoutes,
  filterMenuRecords,
  isBlockedMenuPath,
};
