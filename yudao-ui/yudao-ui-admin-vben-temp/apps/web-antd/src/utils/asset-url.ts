function normalizeBasePath(basePath: string) {
  if (!basePath || basePath === '/') {
    return '';
  }
  return basePath.endsWith('/') ? basePath.slice(0, -1) : basePath;
}

function buildCurrentOrigin() {
  if (typeof window === 'undefined' || !window.location?.origin) {
    return '';
  }
  return window.location.origin;
}

function rewriteKnownPath(pathname: string, search: string, hash: string) {
  const currentOrigin = buildCurrentOrigin();
  const basePath = normalizeBasePath(import.meta.env.VITE_BASE || '/');
  if (!currentOrigin) {
    return `${pathname}${search}${hash}`;
  }
  if (pathname.startsWith('/admin-api/')) {
    return `${currentOrigin}${pathname}${search}${hash}`;
  }
  if (pathname.startsWith('/static/')) {
    return `${currentOrigin}${basePath}${pathname}${search}${hash}`;
  }
  if (pathname.startsWith('/oa/')) {
    return `${currentOrigin}${pathname}${search}${hash}`;
  }
  return `${pathname}${search}${hash}`;
}

function shouldRewriteOrigin(url: URL) {
  if (typeof window === 'undefined') {
    return false;
  }
  if (url.origin === window.location.origin) {
    return false;
  }
  return (
    url.pathname.startsWith('/admin-api/') ||
    url.pathname.startsWith('/static/') ||
    url.hostname === '127.0.0.1' ||
    url.hostname === 'localhost'
  );
}

export function normalizeOaAssetUrl(rawUrl?: null | string) {
  const value = (rawUrl || '').trim();
  if (!value) {
    return '';
  }
  if (
    value.startsWith('data:') ||
    value.startsWith('blob:') ||
    value.startsWith('javascript:')
  ) {
    return value;
  }
  if (value.startsWith('/')) {
    return rewriteKnownPath(value, '', '');
  }
  if (value.startsWith('static/')) {
    return rewriteKnownPath(`/${value}`, '', '');
  }
  if (value.startsWith('admin-api/')) {
    return rewriteKnownPath(`/${value}`, '', '');
  }
  try {
    const currentOrigin = buildCurrentOrigin() || 'http://localhost';
    const parsedUrl = new URL(value, currentOrigin);
    if (shouldRewriteOrigin(parsedUrl)) {
      return rewriteKnownPath(
        parsedUrl.pathname,
        parsedUrl.search,
        parsedUrl.hash,
      );
    }
    return parsedUrl.toString();
  } catch {
    return value;
  }
}
